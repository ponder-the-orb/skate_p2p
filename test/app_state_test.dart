import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/core/network/packet_codec.dart';
import 'package:skate_p2p/core/network/packet_dispatcher.dart';
import 'package:skate_p2p/core/state/app_state.dart';
import 'package:skate_p2p/game/game_engine.dart';
import 'package:skate_p2p/media/rejoin_store.dart';

/// Two AppStates wired to each other the way the relay wires two phones:
/// whatever one sends, the other's dispatcher receives. Nothing else crosses.
class _Table {
  final AppState creator = AppState();
  final AppState joiner = AppState();

  late final PacketDispatcher _toCreator = PacketDispatcher(creator);
  late final PacketDispatcher _toJoiner = PacketDispatcher(joiner);

  final List<Uint8List> creatorSent = [];
  final List<Uint8List> joinerSent = [];

  _Table({int creatorId = 7, int joinerId = 8, int roomCode = 41235}) {
    // The relay never echoes: a sender's packet only ever reaches the peer.
    creator.setSendCallback((packet) {
      creatorSent.add(packet);
      _toJoiner.dispatch(packet);
    });
    joiner.setSendCallback((packet) {
      joinerSent.add(packet);
      _toCreator.dispatch(packet);
    });

    creator.setConnectionStatus(true);
    joiner.setConnectionStatus(true);

    // JOINED, then PEER_JOINED to both sides (PROTOCOL.md §5).
    creator.handleJoined(playerId: creatorId, roomCode: roomCode, role: 1);
    joiner.handleJoined(playerId: joinerId, roomCode: roomCode, role: 2);
    creator.handlePeerJoined(joinerId);
    joiner.handlePeerJoined(creatorId);
  }
}

void main() {
  group('AppState seeds both engines identically', () {
    test('creator and joiner agree on setter, defender and letters', () {
      final table = _Table();

      for (final state in [table.creator, table.joiner]) {
        expect(state.phase, equals(ClientPhase.inMatch));
        expect(state.game.phase, equals(GamePhase.setting));
        expect(state.game.setterId, equals(7)); // creator (role 1) sets first
        expect(state.game.defenderId, equals(8));
        expect(state.game.letters, equals({7: 0, 8: 0}));
      }
    });
  });

  group('AppState local intents put exactly one packet on the wire', () {
    test('setTrick encodes TRICK_SET and lands on the peer', () {
      final table = _Table();

      table.creator.setTrick('kickflip');

      expect(table.creatorSent, hasLength(1));
      expect(
        table.creatorSent.single,
        equals(PacketCodec.encodeTrickSet(senderId: 7, name: 'kickflip')),
      );
      expect(table.joiner.game.currentTrickName, equals('kickflip'));
      expect(table.joiner.game.trickDeclared, isTrue);
    });

    test('an unnamed trick crosses the wire as nameLen 0', () {
      final table = _Table();

      table.creator.setTrick('');

      expect(
        table.creatorSent.single,
        equals(Uint8List.fromList([0x01, 0x10, 0x00, 0x07, 0x01, 0x00])),
      );
      expect(table.joiner.game.trickDeclared, isTrue);
      expect(table.joiner.game.currentTrickName, equals(''));
    });

    test('an engine-rejected intent sends nothing', () {
      final table = _Table();

      // The joiner is the defender: it cannot set a trick.
      table.joiner.setTrick('impossible');

      expect(table.joinerSent, isEmpty);
      expect(table.joiner.game.lastRejectedReason, isNotNull);
      expect(table.creator.game.trickDeclared, isFalse);

      // Nor can the defender report a result while the setter is up.
      table.joiner.reportResult(true);
      expect(table.joinerSent, isEmpty);
      expect(table.creator.game.phase, equals(GamePhase.setting));
    });
  });

  group('AppState drives both engines to the same gameOver', () {
    test('scripted local + remote sequence ends identically on both', () {
      final table = _Table();
      final creator = table.creator;
      final joiner = table.joiner;

      // Round 0: setter bails — roles swap, nobody gets a letter.
      creator.setTrick('hardflip');
      creator.reportResult(false);

      for (final state in [creator, joiner]) {
        expect(state.game.phase, equals(GamePhase.setting));
        expect(state.game.setterId, equals(8)); // roles swapped
        expect(state.game.defenderId, equals(7));
        expect(state.game.letters, equals({7: 0, 8: 0}));
        expect(state.game.trickDeclared, isFalse);
      }

      // Player 8 now sets. It lands; player 7 matches it once (no letter),
      // then bails five times and spells S-K-A-T-E.
      joiner.setTrick('ollie');
      joiner.reportResult(true);
      creator.reportResult(true); // defender matched it
      for (final state in [creator, joiner]) {
        expect(state.game.phase, equals(GamePhase.setting));
        expect(state.game.setterId, equals(8)); // same setter, new trick
        expect(state.game.letters, equals({7: 0, 8: 0}));
      }

      for (var letter = 1; letter <= 5; letter++) {
        joiner.setTrick(letter.isEven ? '' : 'switch flip $letter');
        joiner.reportResult(true);
        creator.reportResult(false); // defender bails, takes a letter

        for (final state in [creator, joiner]) {
          expect(state.game.letters[7], equals(letter));
          expect(state.game.letters[8], equals(0));
        }
      }

      for (final state in [creator, joiner]) {
        expect(state.game.phase, equals(GamePhase.gameOver));
        expect(state.game.winnerId, equals(8));
        expect(state.game.letters, equals({7: 5, 8: 0}));
      }

      // A rematch needs both votes; one alone only records a vote.
      creator.voteRematch();
      for (final state in [creator, joiner]) {
        expect(state.game.phase, equals(GamePhase.gameOver));
        expect(state.game.rematchVotes, equals({7}));
      }

      joiner.voteRematch();
      for (final state in [creator, joiner]) {
        expect(state.game.phase, equals(GamePhase.setting));
        expect(state.game.letters, equals({7: 0, 8: 0}));
        expect(state.game.rematchVotes, isEmpty);
        expect(state.game.winnerId, isNull);
        // Whoever defended first last game sets first now (ARCHITECTURE §5):
        // player 7 set first last game, so player 8 opens the rematch.
        expect(state.game.setterId, equals(8));
        expect(state.game.defenderId, equals(7));
      }
    });
  });

  group('AppState control-flow resets', () {
    test('leaving a match clears the engine and the identity', () {
      final table = _Table();
      table.creator.setTrick('bigspin');

      var reconnected = false;
      table.creator.setReconnectCallback(() => reconnected = true);
      table.creator.handleLeaveMatch();

      expect(reconnected, isTrue);
      expect(table.creator.game.phase, equals(GamePhase.lobby));
      expect(table.creator.playerId, isNull);
      expect(table.creator.peerId, isNull);
      expect(table.creator.notice, equals('Left match.'));
    });

    test('PEER_LEFT abandons the engine before returning to the lobby', () {
      final table = _Table();

      var reconnected = false;
      table.joiner.setReconnectCallback(() => reconnected = true);
      table.joiner.handlePeerLeft(7);

      expect(table.joiner.game.phase, equals(GamePhase.abandoned));
      expect(reconnected, isTrue);
      expect(table.joiner.playerId, isNull);
    });
  });

  group('AppState reconnect grace — survivor side', () {
    test('PEER_DISCONNECTED marks the wait and leaves the engine alone', () {
      final table = _Table();
      table.creator.setTrick('kickflip');
      final before = table.joiner.game;

      table.joiner.handlePeerDisconnected(7, 120);

      expect(table.joiner.peerDisconnected, isTrue);
      expect(table.joiner.graceSeconds, equals(120));
      // Nothing about the game has changed — only PEER_LEFT abandons it.
      expect(table.joiner.game, same(before));
      expect(table.joiner.game.phase, equals(GamePhase.setting));
      expect(table.joinerSent, isEmpty);
    });

    test('PEER_RECONNECTED clears the wait and sends exactly one 0x12', () {
      final table = _midGame();
      table.joiner.handlePeerDisconnected(7, 120);
      table.joinerSent.clear();

      table.joiner.handlePeerReconnected(7);

      expect(table.joiner.peerDisconnected, isFalse);
      expect(table.joiner.graceSeconds, equals(0));
      expect(table.joinerSent, hasLength(1));
      expect(table.joinerSent.single[1], equals(0x12));

      final sync = PacketCodec.decode(table.joinerSent.single);
      expect(sync, isA<StateSyncPacket>());
      expect((sync as StateSyncPacket).senderId, equals(8));
    });

    test('a survivor still in the lobby has no snapshot to send', () {
      final app = AppState();
      final sent = <Uint8List>[];
      app.setSendCallback(sent.add);
      app.setConnectionStatus(true);
      app.handleJoined(playerId: 7, roomCode: 41235, role: 1);

      app.handlePeerReconnected(8);

      // No game in progress: this side is the rejoiner, not the survivor.
      expect(sent, isEmpty);
      expect(app.awaitingSync, isTrue);
      expect(app.phase, equals(ClientPhase.inMatch));
    });
  });

  group('AppState reconnect grace — the rejoiner resumes the same game', () {
    test('a fresh AppState fed JOINED + 0x06 + 0x12 matches the survivor', () {
      final table = _midGame();
      final survivor = table.joiner; // player 8 stayed
      table.joiner.handlePeerDisconnected(7, 120);
      table.joinerSent.clear();
      survivor.handlePeerReconnected(7);
      final stateSync = table.joinerSent.single;

      // Player 7 relaunches the app: a brand new AppState, no history at all.
      final rejoiner = AppState();
      final toRejoiner = PacketDispatcher(rejoiner);
      rejoiner.setConnectionStatus(true);

      // The server re-seats the original id and role in JOINED.
      rejoiner.handleJoined(playerId: 7, roomCode: 41235, role: 1);
      expect(rejoiner.game.phase, equals(GamePhase.lobby));

      toRejoiner.dispatch(peerReconnectedFixture(8));
      expect(rejoiner.awaitingSync, isTrue);
      expect(rejoiner.peerId, equals(8));
      expect(rejoiner.game.phase, equals(GamePhase.lobby)); // still nothing

      toRejoiner.dispatch(stateSync);

      expect(rejoiner.awaitingSync, isFalse);
      expect(rejoiner.phase, equals(ClientPhase.inMatch));
      expectSameGame(rejoiner.game, survivor.game);
    });

    test('the snapshot survives a game that is already over', () {
      final table = _Table();
      final creator = table.creator;
      final joiner = table.joiner;

      // Player 8 spells S.K.A.T.E. and player 7 alone votes for a rematch.
      for (var letter = 1; letter <= 5; letter++) {
        creator.setTrick('trick $letter');
        creator.reportResult(true);
        joiner.reportResult(false);
      }
      creator.voteRematch();
      expect(creator.game.phase, equals(GamePhase.gameOver));

      table.creatorSent.clear();
      creator.handlePeerDisconnected(8, 120);
      creator.handlePeerReconnected(8);

      final rejoiner = AppState();
      final toRejoiner = PacketDispatcher(rejoiner);
      rejoiner.setConnectionStatus(true);
      rejoiner.handleJoined(playerId: 8, roomCode: 41235, role: 2);
      toRejoiner.dispatch(peerReconnectedFixture(7));
      toRejoiner.dispatch(table.creatorSent.single);

      expectSameGame(rejoiner.game, creator.game);
      expect(rejoiner.game.phase, equals(GamePhase.gameOver));
      expect(rejoiner.game.winnerId, equals(7));
      expect(rejoiner.game.rematchVotes, equals({7}));
      expect(rejoiner.game.letters, equals({7: 0, 8: 5}));
    });

    test('an undeclared trick stays undeclared across the sync', () {
      final table = _Table(); // fresh game: setting, nothing declared
      table.creatorSent.clear();
      table.creator.handlePeerReconnected(8);

      final rejoiner = AppState();
      final toRejoiner = PacketDispatcher(rejoiner);
      rejoiner.setConnectionStatus(true);
      rejoiner.handleJoined(playerId: 8, roomCode: 41235, role: 2);
      toRejoiner.dispatch(peerReconnectedFixture(7));
      toRejoiner.dispatch(table.creatorSent.single);

      expect(rejoiner.game.trickDeclared, isFalse);
      expect(rejoiner.game.currentTrickName, isNull);
      expectSameGame(rejoiner.game, table.creator.game);
    });

    test('a synced rejoiner can play on, and the survivor agrees', () {
      final table = _midGame();
      table.joinerSent.clear();
      table.joiner.handlePeerReconnected(7);
      final stateSync = table.joinerSent.single;

      // Rebuild player 7 and wire it back to the survivor, relay-style.
      final rejoiner = AppState();
      final toRejoiner = PacketDispatcher(rejoiner);
      final toSurvivor = PacketDispatcher(table.joiner);
      rejoiner.setSendCallback(toSurvivor.dispatch);
      rejoiner.setConnectionStatus(true);
      rejoiner.handleJoined(playerId: 7, roomCode: 41235, role: 1);
      toRejoiner.dispatch(peerReconnectedFixture(8));
      toRejoiner.dispatch(stateSync);

      // Player 7 is the defender mid-defence: it bails and takes a letter.
      expect(rejoiner.game.phase, equals(GamePhase.defending));
      rejoiner.reportResult(false);

      expectSameGame(rejoiner.game, table.joiner.game);
      expect(rejoiner.game.letters[7], equals(2));
      expect(rejoiner.game.phase, equals(GamePhase.setting));
    });
  });

  group('AppState accepts STATE_SYNC only while awaiting one', () {
    test('a 0x12 arriving mid-match is dropped', () {
      final table = _midGame();
      table.joinerSent.clear();
      table.joiner.handlePeerReconnected(7);
      final stateSync = table.joinerSent.single;

      // The survivor is not awaiting anything: its own snapshot must bounce.
      final before = table.joiner.game;
      PacketDispatcher(table.joiner).dispatch(stateSync);

      expect(table.joiner.game, same(before));
      expect(table.joiner.awaitingSync, isFalse);
    });

    test('a 0x12 arriving before PEER_RECONNECTED is dropped', () {
      final table = _midGame();
      table.joinerSent.clear();
      table.joiner.handlePeerReconnected(7);

      final rejoiner = AppState();
      final toRejoiner = PacketDispatcher(rejoiner);
      rejoiner.setConnectionStatus(true);
      rejoiner.handleJoined(playerId: 7, roomCode: 41235, role: 1);

      toRejoiner.dispatch(table.joinerSent.single); // no 0x06 yet

      expect(rejoiner.game.phase, equals(GamePhase.lobby));
      expect(rejoiner.awaitingSync, isFalse);
    });

    test('a second 0x12 after the sync is dropped', () {
      final table = _midGame();
      table.joinerSent.clear();
      table.joiner.handlePeerReconnected(7);
      final stateSync = table.joinerSent.single;

      final rejoiner = AppState();
      final toRejoiner = PacketDispatcher(rejoiner);
      rejoiner.setConnectionStatus(true);
      rejoiner.handleJoined(playerId: 7, roomCode: 41235, role: 1);
      toRejoiner.dispatch(peerReconnectedFixture(8));
      toRejoiner.dispatch(stateSync);

      final installed = rejoiner.game;
      toRejoiner.dispatch(stateSync);

      expect(rejoiner.game, same(installed));
    });
  });

  group('AppState reconnect grace resets with the identity', () {
    test('PEER_LEFT during grace clears the banner state', () {
      final table = _midGame();
      table.joiner.handlePeerDisconnected(7, 120);

      table.joiner.handlePeerLeft(7);

      expect(table.joiner.game.phase, equals(GamePhase.abandoned));
      expect(table.joiner.peerDisconnected, isFalse);
      expect(table.joiner.graceSeconds, equals(0));
      expect(table.joiner.awaitingSync, isFalse);
    });
  });

  group('rejoin persistence rides the grace window', () {
    late Directory documents;
    late RejoinStore store;

    setUp(() {
      documents = Directory.systemTemp.createTempSync('skate_rejoin_state');
      store = RejoinStore(documents);
    });

    tearDown(() {
      if (documents.existsSync()) {
        documents.deleteSync(recursive: true);
      }
    });

    /// An AppState mid-game with the store attached, exactly as `main.dart`
    /// wires it. Player 7 created the room and is the setter.
    AppState seated({int roomCode = 41235}) {
      final state = AppState()..attachRejoinStore(store);
      state.setSendCallback((_) {});
      state.setConnectionStatus(true);
      state.handleJoined(playerId: 7, roomCode: roomCode, role: 1);
      state.handlePeerJoined(8);
      return state;
    }

    /// The hooks fire unawaited, but the store serialises its own writes — so
    /// a `load()` queued after them is queued *behind* them.
    Future<RejoinRecord?> settled() => store.load();

    /// Forty minutes ago, truncated to whole milliseconds — the record round
    /// trips through `millisecondsSinceEpoch`, so a microsecond-precise
    /// `DateTime.now()` would never compare equal to what comes back.
    DateTime staleTimestamp() => DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch -
          const Duration(minutes: 40).inMilliseconds,
    );

    test('JOINED saves the room and the seat', () async {
      final state = AppState()..attachRejoinStore(store);
      state.handleJoined(playerId: 7, roomCode: 41235, role: 1);

      final record = await settled();
      expect(record, isNotNull);
      expect(record!.roomCode, equals(41235));
      expect(record.playerId, equals(7));
    });

    test('a local game opcode touches the save', () async {
      final state = seated();
      final stale = staleTimestamp();
      await store.save(41235, 7, at: stale);

      state.setTrick('kickflip');

      final record = await settled();
      // Freshness is last activity, not join time: a long game stays offerable.
      expect(record!.savedAt.isAfter(stale), isTrue);
      expect(record.roomCode, equals(41235));
      expect(record.playerId, equals(7));
    });

    test('a remote game opcode touches the save', () async {
      final state = seated();
      final stale = staleTimestamp();
      await store.save(41235, 7, at: stale);

      state.applyRemoteEvent(TrickSetPacket(senderId: 8, name: 'ollie'));

      // Player 8 is defending, so the engine rejects this — nothing was
      // applied, so nothing is touched.
      expect((await settled())!.savedAt, equals(stale));

      state.setTrick('kickflip');
      state.reportResult(true);
      state.applyRemoteEvent(AttemptResultPacket(senderId: 8, landed: false));

      expect((await settled())!.savedAt.isAfter(stale), isTrue);
    });

    test('touching never invents a save the player never had', () async {
      final state = AppState()..attachRejoinStore(store);
      state.setSendCallback((_) {});
      state.handleJoined(playerId: 7, roomCode: 41235, role: 1);
      state.handlePeerJoined(8);
      await store.clear();

      state.setTrick('kickflip');

      expect(await settled(), isNull);
    });

    test('room-not-found after a Rejoin tap clears the save', () async {
      final state = AppState()..attachRejoinStore(store);
      await store.save(41235, 7);

      state.markRejoinAttempt(41235);
      state.handleRoomError(0x02);

      expect(await settled(), isNull);
      expect(state.errorNotice, equals('Room not found'));
    });

    test('room-not-found after a mistyped manual join keeps the save', () async {
      final state = AppState()..attachRejoinStore(store);
      await store.save(41235, 7);

      // No markRejoinAttempt: the player typed 99999 by hand and fat-fingered
      // it. That must never cost them the game they are still inside grace of.
      state.handleRoomError(0x02);

      expect((await settled())!.roomCode, equals(41235));
    });

    test('room-full after a Rejoin tap keeps the save', () async {
      final state = AppState()..attachRejoinStore(store);
      await store.save(41235, 7);

      state.markRejoinAttempt(41235);
      state.handleRoomError(0x01);

      expect((await settled())!.roomCode, equals(41235));
    });

    test(
      'the pending flag does not survive the answer it waited for',
      () async {
        final state = AppState()..attachRejoinStore(store);
        await store.save(41235, 7);

        state.markRejoinAttempt(41235);
        state.handleRoomError(0x01); // an ERROR clears it, whatever the code
        state.handleRoomError(0x02); // so this one is a plain manual failure

        expect((await settled())!.roomCode, equals(41235));
      },
    );

    test('a JOINED clears the pending flag too', () async {
      final state = AppState()..attachRejoinStore(store);

      state.markRejoinAttempt(41235);
      state.handleJoined(playerId: 7, roomCode: 41235, role: 1);
      state.handleRoomError(0x02); // a later, unrelated manual mistype

      expect((await settled())!.roomCode, equals(41235));
    });

    test('with no store attached the feature is silently off', () async {
      final state = AppState();
      state.setSendCallback((_) {});

      // Every hook, on a state that never got a store. None of them may throw
      // — which is what every pre-existing test in this file relies on.
      state.handleJoined(playerId: 7, roomCode: 41235, role: 1);
      state.handlePeerJoined(8);
      state.setTrick('kickflip');
      state.markRejoinAttempt(41235);
      state.handleRoomError(0x02);

      expect(state.rejoinStore, isNull);
    });
  });
}

/// PEER_RECONNECTED (0x06) as the server sends it.
Uint8List peerReconnectedFixture(int peerId) {
  final bytes = Uint8List(7);
  final data = ByteData.sublistView(bytes);
  data.setUint8(0, 0x01);
  data.setUint8(1, 0x06);
  data.setUint16(2, 0); // senderId = server
  data.setUint8(4, 0x02);
  data.setUint16(5, peerId);
  return bytes;
}

/// A table played into a genuinely mid-game position: player 8 is the setter,
/// has landed "kickflip", player 7 is defending and already carries a letter.
_Table _midGame() {
  final table = _Table();
  table.creator.setTrick('hardflip');
  table.creator.reportResult(false); // roles swap, no letter
  table.joiner.setTrick('ollie');
  table.joiner.reportResult(true);
  table.creator.reportResult(false); // player 7 takes a letter
  table.joiner.setTrick('kickflip');
  table.joiner.reportResult(true); // player 7 is defending again
  table.creatorSent.clear();
  table.joinerSent.clear();
  return table;
}

/// [GameState] has no `==` (it is engine-owned and this ticket changes zero
/// lines of `lib/game/`), so agreement is asserted field by field.
void expectSameGame(GameState actual, GameState expected) {
  expect(actual.phase, equals(expected.phase));
  expect(actual.setterId, equals(expected.setterId));
  expect(actual.defenderId, equals(expected.defenderId));
  expect(actual.firstSetterId, equals(expected.firstSetterId));
  expect(actual.winnerId, equals(expected.winnerId));
  expect(actual.letters, equals(expected.letters));
  expect(actual.rematchVotes, equals(expected.rematchVotes));
  expect(actual.trickDeclared, equals(expected.trickDeclared));
  expect(actual.currentTrickName, equals(expected.currentTrickName));
}
