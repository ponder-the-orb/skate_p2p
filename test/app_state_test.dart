import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/core/network/packet_codec.dart';
import 'package:skate_p2p/core/network/packet_dispatcher.dart';
import 'package:skate_p2p/core/state/app_state.dart';
import 'package:skate_p2p/game/game_engine.dart';

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
}
