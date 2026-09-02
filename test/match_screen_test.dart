import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/core/network/packet_codec.dart';
import 'package:skate_p2p/core/state/app_state.dart';
import 'package:skate_p2p/game/game_engine.dart';
import 'package:skate_p2p/ui/data/trick_presets.dart';
import 'package:skate_p2p/ui/screens/match_screen.dart';
import 'package:skate_p2p/ui/widgets/attempt_timer.dart';

const int _myId = 7;
const int _peerId = 8;

/// A real [AppState] driven exactly as the app drives it: server handlers for
/// identity, public intents for my own moves, `applyRemoteEvent` for the
/// peer's. No send callback is wired — sends no-op, which is all a widget
/// test needs. No mocks, no test-only setters.
AppState _seat({required int role}) {
  final app = AppState();
  app.setConnectionStatus(true);
  app.handleJoined(playerId: _myId, roomCode: 41235, role: role);
  app.handlePeerJoined(_peerId);
  return app;
}

/// Role 1 creates the room and therefore sets first (ARCHITECTURE.md §5).
AppState _seatThatSetsFirst() => _seat(role: 1);

/// Role 2 joins, so the peer sets first.
AppState _seatThatDefendsFirst() => _seat(role: 2);

void _peerSetsTrick(AppState app, String name) =>
    app.applyRemoteEvent(TrickSetPacket(senderId: _peerId, name: name));

void _peerReports(AppState app, {required bool landed}) => app.applyRemoteEvent(
  AttemptResultPacket(senderId: _peerId, landed: landed),
);

Future<void> _pumpMatch(WidgetTester tester, AppState app) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: MatchScreen(appState: app),
    ),
  );
}

void main() {
  group('state 1 — setting, I am the setter, nothing declared', () {
    testWidgets('offers the trick field and SET, and nothing else', (
      tester,
    ) async {
      final app = _seatThatSetsFirst();
      await _pumpMatch(tester, app);

      expect(app.game.phase, GamePhase.setting);
      expect(find.text('YOUR SET'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('SET'), findsOneWidget);
      expect(find.text('LANDED'), findsNothing);
      expect(find.text('BAILED'), findsNothing);
      expect(find.text('WAITING FOR OPPONENT'), findsNothing);
      // Nothing is being attempted yet, so there is nothing to count down.
      expect(find.byType(AttemptTimer), findsNothing);
    });

    testWidgets('an empty field is legal and reads as "Unnamed trick"', (
      tester,
    ) async {
      final app = _seatThatSetsFirst();
      await _pumpMatch(tester, app);

      await tester.tap(find.text('SET'));
      await tester.pump();

      expect(app.game.trickDeclared, isTrue);
      expect(find.text('Unnamed trick'), findsOneWidget);
    });

    testWidgets('offers preset chips above the field', (tester) async {
      final app = _seatThatSetsFirst();
      await _pumpMatch(tester, app);

      // The row scrolls, so only assert on what has to be reachable first.
      expect(find.text(trickPresets.first), findsOneWidget);
    });

    testWidgets('tapping a preset fills the field without declaring', (
      tester,
    ) async {
      final app = _seatThatSetsFirst();
      await _pumpMatch(tester, app);

      await tester.tap(find.text(trickPresets.first));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, trickPresets.first);
      expect(app.game.trickDeclared, isFalse);
      expect(find.text('SET'), findsOneWidget);
    });

    testWidgets('SET after a preset tap declares that exact name', (
      tester,
    ) async {
      final app = _seatThatSetsFirst();
      await _pumpMatch(tester, app);

      await tester.tap(find.text(trickPresets.first));
      await tester.pump();
      await tester.tap(find.text('SET'));
      await tester.pump();

      expect(app.game.trickDeclared, isTrue);
      expect(app.game.currentTrickName, trickPresets.first);
    });

    testWidgets('a filled preset is still editable before SET', (tester) async {
      final app = _seatThatSetsFirst();
      await _pumpMatch(tester, app);

      await tester.tap(find.text(trickPresets.first));
      await tester.pump();
      await tester.enterText(
        find.byType(TextField),
        'switch ${trickPresets.first}',
      );
      await tester.tap(find.text('SET'));
      await tester.pump();

      expect(app.game.currentTrickName, 'switch ${trickPresets.first}');
    });
  });

  group('state 2 — setting, I am the setter, trick declared', () {
    testWidgets('shows my trick and LANDED / BAILED', (tester) async {
      final app = _seatThatSetsFirst();
      await _pumpMatch(tester, app);

      await tester.enterText(find.byType(TextField), 'kickflip');
      await tester.tap(find.text('SET'));
      await tester.pump();

      expect(app.game.phase, GamePhase.setting);
      expect(find.text('YOUR ATTEMPT'), findsOneWidget);
      expect(find.text('kickflip'), findsOneWidget);
      expect(find.text('LANDED'), findsOneWidget);
      expect(find.text('BAILED'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('SET'), findsNothing);
      expect(find.text(trickPresets.first), findsNothing);
      // The attempt is mine, so I get the advisory clock, on a full minute.
      expect(find.byType(AttemptTimer), findsOneWidget);
      expect(find.text('1:00'), findsOneWidget);

      await _leaveMatchScreen(tester);
    });
  });

  group('state 3 — setting, the peer is the setter', () {
    testWidgets('waits, with the opponent clearly up', (tester) async {
      final app = _seatThatDefendsFirst();
      _peerSetsTrick(app, 'heelflip');
      await _pumpMatch(tester, app);

      expect(app.game.phase, GamePhase.setting);
      expect(app.game.setterId, _peerId);
      expect(find.text('OPPONENT IS UP'), findsOneWidget);
      expect(find.text('UP'), findsOneWidget);
      expect(find.text('WAITING FOR OPPONENT'), findsOneWidget);
      expect(find.text('heelflip'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('LANDED'), findsNothing);
      // The waiting player's screen is unchanged: no second clock.
      expect(find.byType(AttemptTimer), findsNothing);
    });
  });

  group('state 4 — defending, I am the defender', () {
    testWidgets('shows their trick and LANDED / BAILED', (tester) async {
      final app = _seatThatDefendsFirst();
      _peerSetsTrick(app, 'tre flip');
      _peerReports(app, landed: true);
      await _pumpMatch(tester, app);

      expect(app.game.phase, GamePhase.defending);
      expect(app.game.defenderId, _myId);
      expect(find.text('MATCH IT'), findsOneWidget);
      expect(find.text('tre flip'), findsOneWidget);
      expect(find.text('LANDED'), findsOneWidget);
      expect(find.text('BAILED'), findsOneWidget);
      expect(find.text('WAITING FOR OPPONENT'), findsNothing);
      // Defending is an attempt too — my clock, again on a full minute.
      expect(find.byType(AttemptTimer), findsOneWidget);
      expect(find.text('1:00'), findsOneWidget);

      await _leaveMatchScreen(tester);
    });
  });

  group('state 5 — defending, the peer defends', () {
    testWidgets('waits with no controls of my own', (tester) async {
      final app = _seatThatSetsFirst();
      app.setTrick('nollie flip');
      app.reportResult(true);
      await _pumpMatch(tester, app);

      expect(app.game.phase, GamePhase.defending);
      expect(app.game.defenderId, _peerId);
      expect(find.text('OPPONENT IS UP'), findsOneWidget);
      expect(find.text('UP'), findsOneWidget);
      expect(find.text('nollie flip'), findsOneWidget);
      expect(find.text('WAITING FOR OPPONENT'), findsOneWidget);
      expect(find.text('LANDED'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(AttemptTimer), findsNothing);
    });
  });

  group('state 6 — game over', () {
    testWidgets('winning shows WIN, the final letters and REMATCH', (
      tester,
    ) async {
      final app = _seatThatSetsFirst();
      _playUntilPeerSpellsSkate(app);
      await _pumpMatch(tester, app);

      expect(app.game.phase, GamePhase.gameOver);
      expect(app.game.winnerId, _myId);
      expect(find.text('YOU WIN'), findsOneWidget);
      expect(find.text('YOU LOSE'), findsNothing);
      expect(find.text('FINAL'), findsOneWidget);
      expect(find.text('REMATCH'), findsOneWidget);
      // Both S·K·A·T·E tracks are on the overlay, plus the board behind it.
      expect(find.text('E'), findsNWidgets(4));
      expect(find.byType(AttemptTimer), findsNothing);
    });

    testWidgets('losing shows LOSE', (tester) async {
      final app = _seatThatDefendsFirst();
      _playUntilISpellSkate(app);
      await _pumpMatch(tester, app);

      expect(app.game.winnerId, _peerId);
      expect(find.text('YOU LOSE'), findsOneWidget);
      expect(find.text('YOU WIN'), findsNothing);
    });

    testWidgets('after my vote it waits for the opponent', (tester) async {
      final app = _seatThatSetsFirst();
      _playUntilPeerSpellsSkate(app);
      await _pumpMatch(tester, app);

      await tester.tap(find.text('REMATCH'));
      await tester.pump();

      expect(app.game.rematchVotes, {_myId});
      expect(find.text('Waiting for opponent…'), findsOneWidget);
      expect(find.text('REMATCH'), findsNothing);
    });

    testWidgets('a peer who votes first says so', (tester) async {
      final app = _seatThatSetsFirst();
      _playUntilPeerSpellsSkate(app);
      app.applyRemoteEvent(RematchPacket(senderId: _peerId));
      await _pumpMatch(tester, app);

      expect(app.game.phase, GamePhase.gameOver);
      expect(find.text('Opponent wants a rematch'), findsOneWidget);
      expect(find.text('REMATCH'), findsOneWidget);
    });
  });

  group('the attempt countdown (advisory only)', () {
    testWidgets('counts down while the attempt is mine', (tester) async {
      final app = _seatThatSetsFirst();
      await _pumpMatch(tester, app);

      app.setTrick('switch heel');
      await tester.pump();
      expect(find.text('1:00'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      expect(find.text('0:50'), findsOneWidget);

      await _leaveMatchScreen(tester);
    });

    testWidgets('declaring a new trick restarts it', (tester) async {
      final app = _seatThatSetsFirst();
      await _pumpMatch(tester, app);

      app.setTrick('first trick');
      await tester.pump();
      await tester.pump(const Duration(seconds: 12));
      expect(find.text('0:48'), findsOneWidget);

      // I land it, the peer bails the match: same setter, new trick to name.
      app.reportResult(true);
      await tester.pump();
      _peerReports(app, landed: false);
      await tester.pump();
      expect(find.byType(AttemptTimer), findsNothing);

      app.setTrick('second trick');
      await tester.pump();
      expect(find.text('1:00'), findsOneWidget);
      expect(find.text('0:48'), findsNothing);

      await _leaveMatchScreen(tester);
    });

    testWidgets(
      'at zero it only changes the display — the game does not move',
      (tester) async {
        final app = _seatThatSetsFirst();
        await _pumpMatch(tester, app);

        app.setTrick('impossible');
        await tester.pump();
        final phaseBefore = app.game.phase;

        await tester.pump(const Duration(seconds: attemptSeconds));

        expect(find.text(attemptTimeUpMessage), findsOneWidget);
        // Advisory: no auto-bail, no letter, no event (ADR-003). Still my call.
        expect(app.game.phase, phaseBefore);
        expect(app.game.letters[_myId], 0);
        expect(app.game.trickDeclared, isTrue);
        expect(find.text('LANDED'), findsOneWidget);
        expect(find.text('BAILED'), findsOneWidget);

        await _leaveMatchScreen(tester);
      },
    );
  });

  group('reconnect grace — the survivor waits', () {
    testWidgets('banners the countdown announced by the server', (
      tester,
    ) async {
      final app = _seatThatSetsFirst();
      app.handlePeerDisconnected(_peerId, 120);
      await _pumpMatch(tester, app);

      expect(find.text(reconnectingLabel(120)), findsOneWidget);
      expect(find.text(reconnectingImminentLabel), findsNothing);

      await _leaveMatchScreen(tester);
    });

    testWidgets('the banner counts down locally, second by second', (
      tester,
    ) async {
      final app = _seatThatSetsFirst();
      app.handlePeerDisconnected(_peerId, 3);
      await _pumpMatch(tester, app);

      expect(find.text(reconnectingLabel(3)), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text(reconnectingLabel(2)), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text(reconnectingLabel(1)), findsOneWidget);

      // At zero the clock stops talking in numbers: PEER_LEFT is the only
      // thing that can actually end the game, and it has not arrived.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(reconnectingImminentLabel), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(reconnectingImminentLabel), findsOneWidget);
      expect(app.game.phase, equals(GamePhase.setting)); // still not abandoned

      await _leaveMatchScreen(tester);
    });

    testWidgets('SET is disabled while the peer is away', (tester) async {
      final app = _seatThatSetsFirst();
      app.handlePeerDisconnected(_peerId, 120);
      await _pumpMatch(tester, app);

      final setButton = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('SET'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(setButton.onPressed, isNull);

      await tester.tap(find.text('SET'), warnIfMissed: false);
      await tester.pump();
      expect(app.game.trickDeclared, isFalse);

      await _leaveMatchScreen(tester);
    });

    testWidgets('LANDED and BAILED are disabled while the peer is away', (
      tester,
    ) async {
      final app = _seatThatSetsFirst();
      app.setTrick('kickflip'); // state 2: my attempt
      app.handlePeerDisconnected(_peerId, 120);
      await _pumpMatch(tester, app);

      final landed = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('LANDED'),
          matching: find.byType(ElevatedButton),
        ),
      );
      final bailed = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('BAILED'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(landed.onPressed, isNull);
      expect(bailed.onPressed, isNull);

      await tester.tap(find.text('LANDED'), warnIfMissed: false);
      await tester.pump();
      expect(app.game.phase, equals(GamePhase.setting)); // no attempt landed

      await _leaveMatchScreen(tester);
    });

    testWidgets('the banner and the buttons come back on reconnect', (
      tester,
    ) async {
      final app = _seatThatSetsFirst();
      app.handlePeerDisconnected(_peerId, 120);
      await _pumpMatch(tester, app);
      expect(find.text(reconnectingLabel(120)), findsOneWidget);

      app.handlePeerReconnected(_peerId);
      await tester.pump();

      expect(find.text(reconnectingLabel(120)), findsNothing);
      expect(find.text(reconnectingImminentLabel), findsNothing);
      final setButton = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('SET'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(setButton.onPressed, isNotNull);

      await _leaveMatchScreen(tester);
    });
  });

  group('reconnect grace — the rejoiner restores', () {
    testWidgets('shows the restoring state while awaiting the snapshot', (
      tester,
    ) async {
      final app = AppState();
      app.setConnectionStatus(true);
      app.handleJoined(playerId: _myId, roomCode: 41235, role: 1);
      app.handlePeerReconnected(_peerId);
      expect(app.awaitingSync, isTrue);

      await _pumpMatch(tester, app);

      expect(find.text(restoringLabel), findsOneWidget);
      // Nothing about the game is drawn before it is known.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('SET'), findsNothing);
      expect(find.text('WAITING FOR OPPONENT'), findsNothing);

      await _leaveMatchScreen(tester);
    });

    testWidgets('the snapshot replaces it with the real game', (tester) async {
      final app = AppState();
      app.setConnectionStatus(true);
      app.handleJoined(playerId: _myId, roomCode: 41235, role: 1);
      app.handlePeerReconnected(_peerId);
      await _pumpMatch(tester, app);

      app.applyStateSync(
        StateSyncPacket(
          senderId: _peerId,
          phase: 2, // defending
          setterId: _peerId,
          defenderId: _myId,
          firstSetterId: _myId,
          winnerId: null,
          letters: const {_myId: 2, _peerId: 1},
          rematchVotes: const {},
          trickDeclared: true,
          trickName: 'kickflip',
        ),
      );
      await tester.pump();

      expect(find.text(restoringLabel), findsNothing);
      expect(find.text('MATCH IT'), findsOneWidget);
      expect(find.text('kickflip'), findsOneWidget);
      expect(find.text('LANDED'), findsOneWidget);

      await _leaveMatchScreen(tester);
    });
  });
}

/// Tears the screen down so a running countdown can't outlive its test.
Future<void> _leaveMatchScreen(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

/// I set and land five tricks; the peer bails every match and spells S.K.A.T.E.
void _playUntilPeerSpellsSkate(AppState app) {
  for (var i = 0; i < 5; i++) {
    app.setTrick('trick $i');
    app.reportResult(true);
    _peerReports(app, landed: false);
  }
}

/// The mirror image: the peer sets and lands, I bail every match.
void _playUntilISpellSkate(AppState app) {
  for (var i = 0; i < 5; i++) {
    _peerSetsTrick(app, 'trick $i');
    _peerReports(app, landed: true);
    app.reportResult(false);
  }
}
