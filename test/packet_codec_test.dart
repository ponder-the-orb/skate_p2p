import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/core/network/packet_codec.dart';

void main() {
  group('PacketCodec §7 Worked Examples & Parsing', () {
    test('encodeJoin (create new room) matches spec exactly', () {
      final bytes = PacketCodec.encodeJoin(roomCode: 0);

      // Spec: 01 01 00 00 04 00 00 00 00
      final expected = Uint8List.fromList([
        0x01, // ver
        0x01, // op (JOIN)
        0x00, 0x00, // senderId = 0
        0x04, // payloadLen = 4
        0x00, 0x00, 0x00, 0x00, // roomCode = 0
      ]);

      expect(bytes, equals(expected));
    });

    test('decode JOINED fixture matches spec values exactly', () {
      // Spec: 01 02 00 00 07 00 07 00 00 A1 13 01
      // playerId = 7, roomCode = 41235 (0xA113), role = 1
      final fixture = Uint8List.fromList([
        0x01, // ver
        0x02, // op (JOINED)
        0x00, 0x00, // senderId = 0
        0x07, // payloadLen = 7
        0x00, 0x07, // playerId = 7
        0x00, 0x00, 0xA1, 0x13, // roomCode = 41235
        0x01, // role = 1
      ]);

      final packet = PacketCodec.decode(fixture);
      expect(packet, isA<JoinedPacket>());

      final joined = packet as JoinedPacket;
      expect(joined.senderId, equals(0));
      expect(joined.playerId, equals(7));
      expect(joined.roomCode, equals(41235));
      expect(joined.role, equals(1));
    });

    test('decode PEER_JOINED fixture parses successfully', () {
      final fixture = Uint8List.fromList([
        0x01, // ver
        0x03, // op (PEER_JOINED)
        0x00, 0x00, // senderId = 0
        0x02, // payloadLen = 2
        0x00, 0x0C, // peerId = 12
      ]);

      final packet = PacketCodec.decode(fixture);
      expect(packet, isA<PeerJoinedPacket>());

      final peerJoined = packet as PeerJoinedPacket;
      expect(peerJoined.senderId, equals(0));
      expect(peerJoined.peerId, equals(12));
    });

    test('decode PEER_LEFT fixture parses successfully', () {
      final fixture = Uint8List.fromList([
        0x01, // ver
        0x04, // op (PEER_LEFT)
        0x00, 0x00, // senderId = 0
        0x02, // payloadLen = 2
        0x00, 0x0D, // peerId = 13
      ]);

      final packet = PacketCodec.decode(fixture);
      expect(packet, isA<PeerLeftPacket>());

      final peerLeft = packet as PeerLeftPacket;
      expect(peerLeft.senderId, equals(0));
      expect(peerLeft.peerId, equals(13));
    });

    test('decode ERROR fixture parses successfully', () {
      final fixture = Uint8List.fromList([
        0x01, // ver
        0x0F, // op (ERROR)
        0x00, 0x00, // senderId = 0
        0x01, // payloadLen = 1
        0x02, // errorCode = 0x02 (room not found)
      ]);

      final packet = PacketCodec.decode(fixture);
      expect(packet, isA<ErrorPacket>());

      final err = packet as ErrorPacket;
      expect(err.senderId, equals(0));
      expect(err.errorCode, equals(2));
    });
  });

  group('PacketCodec Malformed Inputs Validation', () {
    test('truncated packet (less than header size) returns null', () {
      final truncated = Uint8List.fromList([0x01, 0x01, 0x00]);
      expect(PacketCodec.decode(truncated), isNull);
    });

    test('unsupported version byte returns null', () {
      final badVersion = Uint8List.fromList([
        0x02,
        0x01,
        0x00,
        0x00,
        0x04,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
      expect(PacketCodec.decode(badVersion), isNull);
    });

    test('length mismatch (longer than payloadLen states) returns null', () {
      final tooLong = Uint8List.fromList([
        0x01,
        0x01,
        0x00,
        0x00,
        0x04,
        0x00,
        0x00,
        0x00,
        0x00,
        0xAA,
      ]);
      expect(PacketCodec.decode(tooLong), isNull);
    });

    test('length mismatch (shorter than payloadLen states) returns null', () {
      final tooShort = Uint8List.fromList([
        0x01,
        0x01,
        0x00,
        0x00,
        0x04,
        0x00,
        0x00,
      ]);
      expect(PacketCodec.decode(tooShort), isNull);
    });

    test('unknown opcode returns null', () {
      final unknownOp = Uint8List.fromList([
        0x01,
        0x99,
        0x00,
        0x00,
        0x01,
        0x00,
      ]);
      expect(PacketCodec.decode(unknownOp), isNull);
    });

    test('malformed opcode payload length mismatch returns null', () {
      // JOIN opcode 0x01 expected payload length is 4, but we give it 2
      final badPayloadLen = Uint8List.fromList([
        0x01,
        0x01,
        0x00,
        0x00,
        0x02,
        0x00,
        0x00,
      ]);
      expect(PacketCodec.decode(badPayloadLen), isNull);
    });
  });
}
