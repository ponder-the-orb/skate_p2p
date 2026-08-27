import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/core/network/binary_packer.dart';

void main() {
  group('BinaryPacker round-trips', () {
    test('score update (0x02): pack then parse back every field', () {
      final Uint8List packet = BinaryPacker.packScoreUpdate(
        senderId: 1024,
        lettersCount: 3,
      );

      expect(packet.length, equals(5));

      final ByteData data = ByteData.sublistView(packet);
      expect(data.getUint8(0), equals(0x02)); // opcode
      expect(data.getUint16(1), equals(1024)); // senderId (big-endian)
      expect(data.getUint8(3), equals(1)); // payloadLen
      expect(data.getUint8(4), equals(3)); // lettersCount
    });

    test('turn state (0x03): pack then parse back every field', () {
      final Uint8List packet = BinaryPacker.packTurnState(
        senderId: 42,
        isMyTurn: true,
      );

      expect(packet.length, equals(5));

      final ByteData data = ByteData.sublistView(packet);
      expect(data.getUint8(0), equals(0x03)); // opcode
      expect(data.getUint16(1), equals(42)); // senderId (big-endian)
      expect(data.getUint8(3), equals(1)); // payloadLen
      expect(data.getUint8(4), equals(1)); // turn flag

      final ByteData notMyTurn = ByteData.sublistView(
        BinaryPacker.packTurnState(senderId: 42, isMyTurn: false),
      );
      expect(notMyTurn.getUint8(4), equals(0));
    });

    test('senderId is written big-endian', () {
      final Uint8List packet = BinaryPacker.packScoreUpdate(
        senderId: 0x0102,
        lettersCount: 0,
      );
      expect(packet[1], equals(0x01)); // high byte first
      expect(packet[2], equals(0x02));
    });
  });
}
