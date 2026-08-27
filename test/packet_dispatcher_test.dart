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

  group('PacketDispatcher applies valid packets', () {
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
