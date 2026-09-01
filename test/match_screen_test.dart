import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/core/network/packet_codec.dart';
import 'package:skate_p2p/core/state/app_state.dart';
import 'package:skate_p2p/game/game_engine.dart';
import 'package:skate_p2p/ui/screens/match_screen.dart';

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
}

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
