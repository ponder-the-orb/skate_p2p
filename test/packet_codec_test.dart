import 'dart:convert';
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

  group('PacketCodec game opcodes — §6/§7 fixtures', () {
    test('encodeTrickSet with an empty name matches the unnamed fixture', () {
      // Spec: 01 10 00 07 01 00 — TRICK_SET, unnamed, from player 7
      final bytes = PacketCodec.encodeTrickSet(senderId: 7, name: '');

      expect(
        bytes,
        equals(Uint8List.fromList([0x01, 0x10, 0x00, 0x07, 0x01, 0x00])),
      );
    });

    test('encodeTrickSet with a name carries nameLen + UTF-8 bytes', () {
      final bytes = PacketCodec.encodeTrickSet(senderId: 7, name: 'kickflip');

      expect(
        bytes,
        equals(
          Uint8List.fromList([
            0x01, // ver
            0x10, // op (TRICK_SET)
            0x00, 0x07, // senderId = 7
            0x09, // payloadLen = 1 + 8
            0x08, // nameLen = 8
            ...utf8.encode('kickflip'),
          ]),
        ),
      );
    });

    test('encodeAttemptResult (landed) matches the §7 fixture', () {
      // Spec: 01 11 00 07 01 01 — player 7 landed it
      final bytes = PacketCodec.encodeAttemptResult(senderId: 7, landed: true);

      expect(
        bytes,
        equals(Uint8List.fromList([0x01, 0x11, 0x00, 0x07, 0x01, 0x01])),
      );
    });

    test('encodeAttemptResult (bailed) writes 0x00', () {
      final bytes = PacketCodec.encodeAttemptResult(senderId: 7, landed: false);

      expect(
        bytes,
        equals(Uint8List.fromList([0x01, 0x11, 0x00, 0x07, 0x01, 0x00])),
      );
    });

    test('encodeRematch matches the zero-payload fixture', () {
      // Spec: 01 13 00 07 00 — REMATCH from player 7
      final bytes = PacketCodec.encodeRematch(senderId: 7);

      expect(bytes, equals(Uint8List.fromList([0x01, 0x13, 0x00, 0x07, 0x00])));
    });

    test('decode TRICK_SET (unnamed) yields an empty name', () {
      final packet = PacketCodec.decode(
        Uint8List.fromList([0x01, 0x10, 0x00, 0x07, 0x01, 0x00]),
      );

      expect(packet, isA<TrickSetPacket>());
      final trick = packet as TrickSetPacket;
      expect(trick.senderId, equals(7));
      expect(trick.name, equals(''));
    });

    test('decode TRICK_SET round-trips a named trick', () {
      final packet = PacketCodec.decode(
        PacketCodec.encodeTrickSet(senderId: 7, name: 'nollie heelflip'),
      );

      expect(packet, isA<TrickSetPacket>());
      expect((packet as TrickSetPacket).name, equals('nollie heelflip'));
    });

    test('decode ATTEMPT_RESULT parses land and bail', () {
      final landed = PacketCodec.decode(
        Uint8List.fromList([0x01, 0x11, 0x00, 0x07, 0x01, 0x01]),
      );
      expect((landed as AttemptResultPacket).landed, isTrue);
      expect(landed.senderId, equals(7));

      final bailed = PacketCodec.decode(
        Uint8List.fromList([0x01, 0x11, 0x00, 0x07, 0x01, 0x00]),
      );
      expect((bailed as AttemptResultPacket).landed, isFalse);
    });

    test('decode REMATCH parses the empty payload', () {
      final packet = PacketCodec.decode(
        Uint8List.fromList([0x01, 0x13, 0x00, 0x07, 0x00]),
      );

      expect(packet, isA<RematchPacket>());
      expect(packet!.senderId, equals(7));
    });
  });

  group('PacketCodec game opcode validation', () {
    test('ATTEMPT_RESULT with a result byte other than 0/1 returns null', () {
      expect(
        PacketCodec.decode(
          Uint8List.fromList([0x01, 0x11, 0x00, 0x07, 0x01, 0x02]),
        ),
        isNull,
      );
      expect(
        PacketCodec.decode(
          Uint8List.fromList([0x01, 0x11, 0x00, 0x07, 0x01, 0xFF]),
        ),
        isNull,
      );
    });

    test('TRICK_SET with a zero-length payload returns null', () {
      // payloadLen 0 means there is not even a nameLen byte.
      expect(
        PacketCodec.decode(Uint8List.fromList([0x01, 0x10, 0x00, 0x07, 0x00])),
        isNull,
      );
    });

    test('TRICK_SET whose nameLen disagrees with payloadLen returns null', () {
      // payloadLen says 1 + 3 bytes of name; nameLen claims 2.
      expect(
        PacketCodec.decode(
          Uint8List.fromList([
            0x01,
            0x10,
            0x00,
            0x07,
            0x04,
            0x02,
            0x61,
            0x62,
            0x63,
          ]),
        ),
        isNull,
      );
    });

    test('TRICK_SET carrying invalid UTF-8 returns null', () {
      expect(
        PacketCodec.decode(
          Uint8List.fromList([0x01, 0x10, 0x00, 0x07, 0x03, 0x02, 0xC3, 0x28]),
        ),
        isNull,
      );
    });

    test('REMATCH with a non-empty payload returns null', () {
      expect(
        PacketCodec.decode(
          Uint8List.fromList([0x01, 0x13, 0x00, 0x07, 0x01, 0x00]),
        ),
        isNull,
      );
    });

    test('reserved SCORE_SYNC (0x12) is an unknown opcode', () {
      expect(
        PacketCodec.decode(Uint8List.fromList([0x01, 0x12, 0x00, 0x07, 0x00])),
        isNull,
      );
    });

    test('an over-long trick name is truncated on a UTF-8 boundary', () {
      // 200 two-byte characters = 400 bytes; only whole characters survive.
      final longName = 'é' * 200;
      final bytes = PacketCodec.encodeTrickSet(senderId: 7, name: longName);

      expect(bytes[4], lessThanOrEqualTo(255)); // payloadLen fits a uint8
      final packet = PacketCodec.decode(bytes);
      expect(packet, isA<TrickSetPacket>());
      // 254 bytes would split a character, so the codec stops at 127 of them.
      expect((packet as TrickSetPacket).name, equals('é' * 127));
    });
  });
}
