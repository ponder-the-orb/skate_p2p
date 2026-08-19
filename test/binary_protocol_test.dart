import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/core/network/binary_packer.dart';
import 'package:skate_p2p/core/network/packet_dispatcher.dart';
import 'package:skate_p2p/core/state/app_state.dart';

void main() {
  group('Binary Protocol Test Suite', () {
    test('BinaryPacker creates correct byte length and opcode for score update', () {
      // Pack a score update: sender 1024, lettersCount 3
      final Uint8List packet = BinaryPacker.packScoreUpdate(
        senderId: 1024,
        lettersCount: 3,
      );

      // Verify strict size: 5 bytes total (1 opcode + 2 senderId + 1 payload length + 1 letters)
      expect(packet.length, equals(5));

      // Verify ByteData parsing matches expectations
      final ByteData data = ByteData.sublistView(packet);
      expect(data.getUint8(0), equals(0x02)); // Opcode
      expect(data.getUint16(1), equals(1024)); // Sender ID
      expect(data.getUint8(3), equals(1));   // Payload length
      expect(data.getUint8(4), equals(3));   // Letters count
    });

    test('PacketDispatcher correctly mutates AppState from raw byte stream', () {
      final AppState state = AppState();
      final PacketDispatcher dispatcher = PacketDispatcher(state);

      // Initial state check
      expect(state.peerLetters, equals(0));

      // Construct a correct 5-byte buffer matching packScoreUpdate
      final ByteData buffer = ByteData(5);
      buffer.setUint8(0, 0x02);
      buffer.setUint16(1, 500);
      buffer.setUint8(3, 1); // length
      buffer.setUint8(4, 4); // lettersCount

      // Dispatch the raw buffer list
      dispatcher.dispatch(buffer.buffer.asUint8List());

      // Verify state was mutated properly
      expect(state.peerLetters, equals(4));
    });
  });
}

