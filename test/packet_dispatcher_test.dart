import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/core/network/packet_codec.dart';
import 'package:skate_p2p/core/network/packet_dispatcher.dart';
import 'package:skate_p2p/core/state/app_state.dart';
import 'package:skate_p2p/game/game_engine.dart';

/// JOINED for the given identity, as the server would send it.
Uint8List joinedFixture({
  required int playerId,
  required int role,
  int roomCode = 41235,
}) {
  final bytes = Uint8List(12);
  final data = ByteData.sublistView(bytes);
  data.setUint8(0, 0x01); // ver
  data.setUint8(1, 0x02); // op (JOINED)
  data.setUint16(2, 0); // senderId = server
  data.setUint8(4, 0x07); // payloadLen
  data.setUint16(5, playerId);
  data.setUint32(7, roomCode);
  data.setUint8(11, role);
  return bytes;
}

Uint8List peerJoinedFixture(int peerId) {
  final bytes = Uint8List(7);
  final data = ByteData.sublistView(bytes);
  data.setUint8(0, 0x01);
  data.setUint8(1, 0x03);
  data.setUint16(2, 0);
  data.setUint8(4, 0x02);
  data.setUint16(5, peerId);
  return bytes;
}

Uint8List peerLeftFixture(int peerId) {
  final bytes = Uint8List(7);
  final data = ByteData.sublistView(bytes);
  data.setUint8(0, 0x01);
  data.setUint8(1, 0x04);
  data.setUint16(2, 0);
  data.setUint8(4, 0x02);
  data.setUint16(5, peerId);
  return bytes;
}

void main() {
  late AppState state;
  late PacketDispatcher dispatcher;

  setUp(() {
    state = AppState();
    dispatcher = PacketDispatcher(state);
  });

  group('PacketDispatcher applies valid v1 control packets', () {
    test(
      'JOINED (role 1) updates app state and transitions to waitingForPeer',
      () {
        expect(state.phase, equals(ClientPhase.disconnected));
        state.setConnectionStatus(true);
        expect(state.phase, equals(ClientPhase.lobbyIdle));

        dispatcher.dispatch(joinedFixture(playerId: 7, role: 1));

        expect(state.phase, equals(ClientPhase.waitingForPeer));
        expect(state.playerId, equals(7));
        expect(state.roomCode, equals(41235));
        expect(state.role, equals(1));
      },
    );

    test(
      'JOINED (role 2) updates app state and transitions directly to inMatch',
      () {
        state.setConnectionStatus(true);

        dispatcher.dispatch(joinedFixture(playerId: 8, role: 2));

        expect(state.phase, equals(ClientPhase.inMatch));
        expect(state.playerId, equals(8));
        expect(state.roomCode, equals(41235));
        expect(state.role, equals(2));
      },
    );

    test('PEER_JOINED seeds the creator\'s engine with itself as setter', () {
      state.setConnectionStatus(true);
      dispatcher.dispatch(joinedFixture(playerId: 7, role: 1));
      expect(state.phase, equals(ClientPhase.waitingForPeer));

      dispatcher.dispatch(peerJoinedFixture(8));

      expect(state.phase, equals(ClientPhase.inMatch));
      expect(state.peerId, equals(8));
      expect(state.game.phase, equals(GamePhase.setting));
      expect(state.game.setterId, equals(7));
      expect(state.game.defenderId, equals(8));
    });

    test('PEER_JOINED seeds the joiner\'s engine with the peer as setter', () {
      state.setConnectionStatus(true);
      dispatcher.dispatch(joinedFixture(playerId: 8, role: 2));

      dispatcher.dispatch(peerJoinedFixture(7));

      expect(state.phase, equals(ClientPhase.inMatch));
      expect(state.peerId, equals(7));
      expect(state.game.phase, equals(GamePhase.setting));
      expect(state.game.setterId, equals(7));
      expect(state.game.defenderId, equals(8));
    });

    test('PEER_LEFT abandons the game, clears identity and reconnects', () {
      state.setConnectionStatus(true);
      bool reconnectCalled = false;
      state.setReconnectCallback(() {
        reconnectCalled = true;
      });

      dispatcher.dispatch(joinedFixture(playerId: 7, role: 1));
      dispatcher.dispatch(peerJoinedFixture(8));
      expect(state.game.phase, equals(GamePhase.setting));

      dispatcher.dispatch(peerLeftFixture(8));

      expect(state.game.phase, equals(GamePhase.abandoned));
      expect(reconnectCalled, isTrue);
      expect(state.playerId, isNull);
      expect(state.peerId, isNull);
      expect(state.roomCode, isNull);
      expect(state.role, isNull);
      expect(state.notice, contains('Peer left'));
    });

    test('ERROR (room full) sets error notice on AppState', () {
      state.setConnectionStatus(true);

      dispatcher.dispatch(
        Uint8List.fromList([0x01, 0x0F, 0x00, 0x00, 0x01, 0x01]),
      );

      expect(state.phase, equals(ClientPhase.lobbyIdle));
      expect(state.errorNotice, equals('Room full'));
    });

    test('ERROR (room not found) sets error notice on AppState', () {
      state.setConnectionStatus(true);

      dispatcher.dispatch(
        Uint8List.fromList([0x01, 0x0F, 0x00, 0x00, 0x01, 0x02]),
      );

      expect(state.phase, equals(ClientPhase.lobbyIdle));
      expect(state.errorNotice, equals('Room not found'));
    });
  });

  group('PacketDispatcher routes v1 game packets into the engine', () {
    setUp(() {
      // This client is the joiner (player 8); the peer (player 7) sets first.
      state.setConnectionStatus(true);
      dispatcher.dispatch(joinedFixture(playerId: 8, role: 2));
      dispatcher.dispatch(peerJoinedFixture(7));
    });

    test('TRICK_SET from the peer declares the trick', () {
      dispatcher.dispatch(
        PacketCodec.encodeTrickSet(senderId: 7, name: 'kickflip'),
      );

      expect(state.game.trickDeclared, isTrue);
      expect(state.game.currentTrickName, equals('kickflip'));
    });

    test('TRICK_SET with an empty name is a legal unnamed trick', () {
      dispatcher.dispatch(PacketCodec.encodeTrickSet(senderId: 7, name: ''));

      expect(state.game.trickDeclared, isTrue);
      expect(state.game.currentTrickName, equals(''));
    });

    test('ATTEMPT_RESULT from the setter drives the phase transition', () {
      dispatcher.dispatch(
        PacketCodec.encodeTrickSet(senderId: 7, name: 'ollie'),
      );
      dispatcher.dispatch(
        PacketCodec.encodeAttemptResult(senderId: 7, landed: true),
      );

      expect(state.game.phase, equals(GamePhase.defending));
      expect(state.game.defenderId, equals(8));
    });

    test('REMATCH from the peer records the peer\'s vote', () {
      // Drive the game to gameOver: this client (8) defends and bails 5 times.
      for (var i = 0; i < 5; i++) {
        dispatcher.dispatch(PacketCodec.encodeTrickSet(senderId: 7, name: ''));
        dispatcher.dispatch(
          PacketCodec.encodeAttemptResult(senderId: 7, landed: true),
        );
        state.reportResult(false);
      }
      expect(state.game.phase, equals(GamePhase.gameOver));
      expect(state.game.winnerId, equals(7));

      dispatcher.dispatch(PacketCodec.encodeRematch(senderId: 7));

      expect(state.game.rematchVotes, equals({7}));
      expect(state.game.phase, equals(GamePhase.gameOver));
    });

    test('a game packet arriving before a peer is known is dropped', () {
      final fresh = AppState();
      final freshDispatcher = PacketDispatcher(fresh);

      expect(
        () => freshDispatcher.dispatch(
          PacketCodec.encodeTrickSet(senderId: 7, name: 'ollie'),
        ),
        returnsNormally,
      );
      expect(fresh.game.phase, equals(GamePhase.lobby));
    });
  });

  group('PacketDispatcher drops malformed input without throwing', () {
    void expectDroppedSilently(List<int> bytes) {
      final phaseBefore = state.game.phase;

      expect(
        () => dispatcher.dispatch(Uint8List.fromList(bytes)),
        returnsNormally,
      );

      expect(state.game.phase, equals(phaseBefore));
    }

    test('empty buffer []', () {
      expectDroppedSilently([]);
    });

    test('truncated single-opcode buffer [0x01]', () {
      expectDroppedSilently([0x01]);
    });

    test('legacy v0 frames no longer decode', () {
      // v0 score (0x02) and turn (0x03) frames: first byte is not 0x01, so
      // they fail the version check and are dropped.
      expectDroppedSilently([0x02, 0x04, 0x00, 0x01, 0x01]);
      expectDroppedSilently([0x03, 0x04, 0x00, 0x01, 0x01]);
    });

    test('header claiming a payload it does not carry', () {
      expectDroppedSilently([0x01, 0x11, 0x00, 0x07, 0x01]);
    });

    test('oversized buffer for a known opcode', () {
      expectDroppedSilently([0x01, 0x11, 0x00, 0x07, 0x01, 0x01, 0xFF, 0xFF]);
    });

    test('unknown opcode', () {
      expectDroppedSilently([0x01, 0x7F, 0x00, 0x01, 0x01, 0x00]);
    });

    test('reserved SCORE_SYNC (0x12) is dropped', () {
      expectDroppedSilently([0x01, 0x12, 0x00, 0x07, 0x00]);
    });

    test('ATTEMPT_RESULT with an out-of-range result byte is dropped', () {
      expectDroppedSilently([0x01, 0x11, 0x00, 0x07, 0x01, 0x42]);
    });

    test('20 random bytes (seeded) never throw', () {
      final random = Random(1337);
      for (var run = 0; run < 50; run++) {
        final garbage = List<int>.generate(20, (_) => random.nextInt(256));
        expect(
          () => dispatcher.dispatch(Uint8List.fromList(garbage)),
          returnsNormally,
        );
      }
    });

    test('non-binary message is dropped', () {
      expect(() => dispatcher.dispatch('not bytes'), returnsNormally);
      expect(state.game.phase, equals(GamePhase.lobby));
    });
  });
}
