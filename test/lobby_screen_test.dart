import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/core/network/packet_codec.dart';
import 'package:skate_p2p/core/network/signaling_service.dart';
import 'package:skate_p2p/core/state/app_state.dart';
import 'package:skate_p2p/media/rejoin_store.dart';
import 'package:skate_p2p/ui/build_info.dart';
import 'package:skate_p2p/ui/screens/lobby_screen.dart';

/// The Rejoin entry, exercised through a real store pointed at a temp
/// directory. `path_provider` is never mocked here — the resolve function it
/// lives behind is manual-pass territory (ADR-008's rider), and everything
/// below it is a leaf that takes its directory as an argument.
///
/// TRAP: `testWidgets` runs the body inside a fake-async zone, where a real
/// disk future never completes. Reads are fine — `RejoinStore` reads
/// synchronously for exactly this reason — but the store's WRITES are async by
/// design, so every one of them here goes through `tester.runAsync`. What a
/// write *causes* on disk (the save cleared by a room-not-found) is asserted
/// in `app_state_test.dart`, in a plain `test` where futures actually resolve.
void main() {
  late Directory documents;
  late RejoinStore store;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('skate_rejoin_lobby');
    store = RejoinStore(documents);
  });

  tearDown(() {
    if (documents.existsSync()) {
      documents.deleteSync(recursive: true);
    }
  });

  /// Seeds the disk through a THROWAWAY store instance, never [store] itself.
  ///
  /// A write chained onto the injected store's queue from inside `runAsync`
  /// would leave that queue holding a future created in the real zone, which
  /// the fake-async zone can never see complete — and the lobby's `load()`
  /// queues behind it. A separate instance writes the same file and leaves the
  /// injected store's queue pristine.
  Future<void> saveOnDisk(
    WidgetTester tester,
    int roomCode,
    int playerId, {
    DateTime? at,
  }) => tester.runAsync(
    () => RejoinStore(documents).save(roomCode, playerId, at: at),
  );

  /// An idle, connected lobby — the screen a relaunched app lands on. Pass
  /// `connected: false` for the other half of the lobby's life, where the
  /// status pill reads DISCONNECTED and offers a RETRY.
  Future<(AppState, _RecordingSignalingService)> pumpLobby(
    WidgetTester tester, {
    RejoinStore? injected,
    RejoinStore? attached,
    bool connected = true,
  }) async {
    final appState = AppState()..setConnectionStatus(connected);
    if (attached != null) appState.attachRejoinStore(attached);
    final signaling = _RecordingSignalingService();

    await tester.pumpWidget(
      MaterialApp(
        home: LobbyScreen(
          appState: appState,
          signalingService: signaling,
          rejoinStore: injected,
        ),
      ),
    );
    // initState's load() resolves on a microtask; this frame flushes it, and
    // the setState it may do lands on the next one.
    await tester.pump();
    await tester.pump();
    return (appState, signaling);
  }

  testWidgets('a fresh save offers a Rejoin', (tester) async {
    await saveOnDisk(tester, 50412, 7);

    await pumpLobby(tester, injected: store);

    expect(find.textContaining(rejoinLabel), findsOneWidget);
    // The code rides along so the player can see which game they are going
    // back to — five digits, as everywhere else in the app. (Not 41235: the
    // Join field's own hint text is "e.g. 41235", which would match too.)
    expect(find.textContaining('50412'), findsOneWidget);
  });

  testWidgets('a save older than the window offers nothing', (tester) async {
    await saveOnDisk(
      tester,
      50412,
      7,
      at: DateTime.now().subtract(rejoinFreshness + const Duration(seconds: 1)),
    );

    await pumpLobby(tester, injected: store);

    expect(find.textContaining(rejoinLabel), findsNothing);
  });

  testWidgets('a save still inside the window counts', (tester) async {
    await saveOnDisk(
      tester,
      50412,
      7,
      at: DateTime.now().subtract(rejoinFreshness - const Duration(seconds: 5)),
    );

    await pumpLobby(tester, injected: store);

    expect(find.textContaining(rejoinLabel), findsOneWidget);
  });

  testWidgets('no save at all offers nothing', (tester) async {
    await pumpLobby(tester, injected: store);

    expect(find.textContaining(rejoinLabel), findsNothing);
    // The rest of the lobby is untouched by a feature that isn't offered.
    expect(find.text('CREATE ROOM'), findsOneWidget);
  });

  testWidgets('a corrupt save offers nothing and does not crash', (
    tester,
  ) async {
    store.file.writeAsStringSync('{not json');

    await pumpLobby(tester, injected: store);

    expect(find.textContaining(rejoinLabel), findsNothing);
    expect(find.text('CREATE ROOM'), findsOneWidget);
  });

  testWidgets('with no store anywhere the lobby is exactly as it was', (
    tester,
  ) async {
    await saveOnDisk(tester, 50412, 7);

    // Nothing injected and nothing attached: the state every pre-existing
    // widget test in this repo runs in.
    final (appState, _) = await pumpLobby(tester);

    expect(appState.rejoinStore, isNull);
    expect(find.textContaining(rejoinLabel), findsNothing);
    expect(find.text('CREATE ROOM'), findsOneWidget);
  });

  testWidgets('the store attached to AppState is used when none is injected', (
    tester,
  ) async {
    await saveOnDisk(tester, 50412, 7);

    await pumpLobby(tester, attached: store);

    expect(find.textContaining(rejoinLabel), findsOneWidget);
  });

  testWidgets('tapping Rejoin sends one plain JOIN with the saved code', (
    tester,
  ) async {
    await saveOnDisk(tester, 50412, 7);

    final (appState, signaling) = await pumpLobby(tester, injected: store);
    await tester.tap(find.textContaining(rejoinLabel));
    await tester.pump();

    // NOTHING else goes on the wire: the server re-seats the original
    // playerId itself (PROTOCOL.md §5), so the saved id is never sent.
    expect(signaling.sent, hasLength(1));
    expect(
      signaling.sent.single,
      equals(PacketCodec.encodeJoin(roomCode: 50412, senderId: 0x0000)),
    );
    // And the attempt is flagged, so a room-not-found may forget the save.
    expect(appState.pendingRejoinCode, equals(50412));
  });

  testWidgets('the lobby prints the build it is', (tester) async {
    await pumpLobby(tester, injected: store);

    // Cosmetic, and on every lobby state — including the disconnected one,
    // which is exactly the screen a confused tester screenshots.
    expect(find.text('v $appVersion'), findsOneWidget);

    await pumpLobby(tester, injected: store, connected: false);
    expect(find.text('v $appVersion'), findsOneWidget);
  });

  testWidgets('a disconnected lobby offers a RETRY that reconnects once', (
    tester,
  ) async {
    final (appState, _) = await pumpLobby(tester, connected: false);

    var reconnects = 0;
    appState.setReconnectCallback(() => reconnects++);

    expect(find.text('DISCONNECTED'), findsOneWidget);
    await tester.tap(find.text(retryLabel));
    await tester.pump();

    expect(reconnects, equals(1));
  });

  testWidgets('a connected lobby has nothing to retry', (tester) async {
    await pumpLobby(tester);

    expect(find.text('CONNECTED'), findsOneWidget);
    expect(find.text(retryLabel), findsNothing);
  });

  testWidgets('a mistyped manual join is not flagged as a rejoin', (
    tester,
  ) async {
    await saveOnDisk(tester, 50412, 7);

    final (appState, signaling) = await pumpLobby(tester, injected: store);

    await tester.enterText(find.byType(TextField), '99999');
    await tester.pump();
    await tester.tap(find.text('JOIN'));
    await tester.pump();

    expect(
      signaling.sent.single,
      equals(PacketCodec.encodeJoin(roomCode: 99999, senderId: 0x0000)),
    );
    // Unflagged, so the "room not found" this earns cannot delete the save.
    expect(appState.pendingRejoinCode, isNull);
  });
}

/// A signaling service with no socket, which keeps what it was asked to send.
/// The real one silently drops sends when unconnected, which is correct in the
/// app and useless in a test.
class _RecordingSignalingService extends SignalingService {
  final List<Uint8List> sent = [];

  @override
  void sendBinary(Uint8List data) => sent.add(data);
}
