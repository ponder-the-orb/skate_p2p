import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/core/network/binary_packer.dart';
import 'package:skate_p2p/core/network/packet_dispatcher.dart';
import 'package:skate_p2p/core/state/app_state.dart';

void main() {
  late AppState state;
  late PacketDispatcher dispatcher;

  setUp(() {
    state = AppState();
    dispatcher = PacketDispatcher(state);
  });

  group('PacketDispatcher applies valid legacy v0 packets', () {
    test('score update (0x02) mutates peer score', () {
      expect(state.peerLetters, equals(0));

      dispatcher.dispatch(
        BinaryPacker.packScoreUpdate(senderId: 500, lettersCount: 4),
      );

      expect(state.peerLetters, equals(4));
    });

    test('turn state (0x03) mutates turn flag', () {
      dispatcher.dispatch(
        BinaryPacker.packTurnState(senderId: 500, isMyTurn: false),
      );
      expect(state.isMyTurn, isFalse);

      dispatcher.dispatch(
        BinaryPacker.packTurnState(senderId: 500, isMyTurn: true),
      );
      expect(state.isMyTurn, isTrue);
    });
  });

  group('PacketDispatcher applies valid v1 control packets', () {
    test(
      'JOINED (role 1) updates app state and transitions to waitingForPeer',
      () {
        expect(state.phase, equals(ClientPhase.disconnected));
        state.setConnectionStatus(true);
        expect(state.phase, equals(ClientPhase.lobbyIdle));

        // JOINED: playerId = 7, roomCode = 41235 (0xA113), role = 1
        final joinedFixture = Uint8List.fromList([
          0x01, // ver
          0x02, // op (JOINED)
          0x00, 0x00, // senderId = 0
          0x07, // payloadLen = 7
          0x00, 0x07, // playerId = 7
          0x00, 0x00, 0xA1, 0x13, // roomCode = 41235
          0x01, // role = 1
        ]);

        dispatcher.dispatch(joinedFixture);

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

        // JOINED: playerId = 8, roomCode = 41235 (0xA113), role = 2
        final joinedFixture = Uint8List.fromList([
          0x01, // ver
          0x02, // op (JOINED)
          0x00, 0x00, // senderId = 0
          0x07, // payloadLen = 7
          0x00, 0x08, // playerId = 8
          0x00, 0x00, 0xA1, 0x13, // roomCode = 41235
          0x02, // role = 2
        ]);

        dispatcher.dispatch(joinedFixture);

        expect(state.phase, equals(ClientPhase.inMatch));
        expect(state.playerId, equals(8));
        expect(state.roomCode, equals(41235));
        expect(state.role, equals(2));
        expect(state.isMyTurn, isFalse); // Joiner defends first
      },
    );

    test('PEER_JOINED transitions Creator to inMatch', () {
      state.setConnectionStatus(true);

      // Transition to waitingForPeer first
      final joinedFixture = Uint8List.fromList([
        0x01,
        0x02,
        0x00,
        0x00,
        0x07,
        0x00,
        0x07,
        0x00,
        0x00,
        0xA1,
        0x13,
        0x01,
      ]);
      dispatcher.dispatch(joinedFixture);
      expect(state.phase, equals(ClientPhase.waitingForPeer));

      // PEER_JOINED: peerId = 8
      final peerJoinedFixture = Uint8List.fromList([
        0x01, // ver
        0x03, // op (PEER_JOINED)
        0x00, 0x00, // senderId = 0
        0x02, // payloadLen = 2
        0x00, 0x08, // peerId = 8
      ]);

      dispatcher.dispatch(peerJoinedFixture);

      expect(state.phase, equals(ClientPhase.inMatch));
      expect(state.isMyTurn, isTrue); // Creator sets first
    });

    test('PEER_LEFT triggers reconnect callback and clears identity', () {
      state.setConnectionStatus(true);
      bool reconnectCalled = false;
      state.setReconnectCallback(() {
        reconnectCalled = true;
      });

      // Join room first
      final joinedFixture = Uint8List.fromList([
        0x01,
        0x02,
        0x00,
        0x00,
        0x07,
        0x00,
        0x07,
        0x00,
        0x00,
        0xA1,
        0x13,
        0x01,
      ]);
      dispatcher.dispatch(joinedFixture);

      // PEER_LEFT: peerId = 8
      final peerLeftFixture = Uint8List.fromList([
        0x01, // ver
        0x04, // op (PEER_LEFT)
        0x00, 0x00, // senderId = 0
        0x02, // payloadLen = 2
        0x00, 0x08, // peerId = 8
      ]);

      dispatcher.dispatch(peerLeftFixture);

      expect(reconnectCalled, isTrue);
      expect(state.playerId, isNull);
      expect(state.roomCode, isNull);
      expect(state.role, isNull);
      expect(state.notice, contains('Peer left'));
    });

    test('ERROR (room full) sets error notice on AppState', () {
      state.setConnectionStatus(true);

      final errorFixture = Uint8List.fromList([
        0x01, // ver
        0x0F, // op (ERROR)
        0x00, 0x00, // senderId = 0
        0x01, // payloadLen = 1
        0x01, // errorCode = 1 (room full)
      ]);

      dispatcher.dispatch(errorFixture);

      expect(state.phase, equals(ClientPhase.lobbyIdle));
      expect(state.errorNotice, equals('Room full'));
    });

    test('ERROR (room not found) sets error notice on AppState', () {
      state.setConnectionStatus(true);

      final errorFixture = Uint8List.fromList([
        0x01, // ver
        0x0F, // op (ERROR)
        0x00, 0x00, // senderId = 0
        0x01, // payloadLen = 1
        0x02, // errorCode = 2 (room not found)
      ]);

      dispatcher.dispatch(errorFixture);

      expect(state.phase, equals(ClientPhase.lobbyIdle));
      expect(state.errorNotice, equals('Room not found'));
    });
  });

  group('PacketDispatcher drops malformed input without throwing', () {
    void expectDroppedSilently(List<int> bytes) {
      final lettersBefore = state.peerLetters;
      final turnBefore = state.isMyTurn;

      expect(
        () => dispatcher.dispatch(Uint8List.fromList(bytes)),
        returnsNormally,
      );

      expect(state.peerLetters, equals(lettersBefore));
      expect(state.isMyTurn, equals(turnBefore));
    }

    test('empty buffer []', () {
      expectDroppedSilently([]);
    });

    test('truncated single-opcode buffer [0x02]', () {
      expectDroppedSilently([0x02]);
    });

    test('header-only buffer claiming a payload it does not carry', () {
      // Header says payloadLen = 1, but no payload byte follows.
      expectDroppedSilently([0x02, 0x00, 0x01, 0x01]);
    });

    test('oversized buffer for a known opcode', () {
      expectDroppedSilently([0x02, 0x00, 0x01, 0x01, 0x03, 0xFF, 0xFF]);
    });

    test('unknown opcode', () {
      expectDroppedSilently([0x7F, 0x00, 0x01, 0x01, 0x00]);
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
      expect(state.peerLetters, equals(0));
    });
  });
}
