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

    test('STATE_SYNC (0x12) with an empty payload returns null', () {
      // 17 fixed bytes are mandatory before the name can even be read.
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

  group('PacketCodec reconnect grace control frames', () {
    test('decode PEER_DISCONNECTED fixture parses peer and window', () {
      final fixture = Uint8List.fromList([
        0x01, // ver
        0x05, // op (PEER_DISCONNECTED)
        0x00, 0x00, // senderId = 0 (server)
        0x04, // payloadLen = 4
        0x00, 0x08, // peerId = 8
        0x00, 0x78, // graceSeconds = 120
      ]);

      final packet = PacketCodec.decode(fixture);
      expect(packet, isA<PeerDisconnectedPacket>());

      final disconnected = packet as PeerDisconnectedPacket;
      expect(disconnected.senderId, equals(0));
      expect(disconnected.peerId, equals(8));
      expect(disconnected.graceSeconds, equals(120));
    });

    test('decode PEER_RECONNECTED fixture parses the returning peer', () {
      final fixture = Uint8List.fromList([
        0x01, // ver
        0x06, // op (PEER_RECONNECTED)
        0x00, 0x00, // senderId = 0 (server)
        0x02, // payloadLen = 2
        0x00, 0x08, // peerId = 8
      ]);

      final packet = PacketCodec.decode(fixture);
      expect(packet, isA<PeerReconnectedPacket>());
      expect((packet as PeerReconnectedPacket).peerId, equals(8));
    });

    test('a PEER_DISCONNECTED with the wrong payload length is dropped', () {
      expect(
        PacketCodec.decode(
          Uint8List.fromList([0x01, 0x05, 0x00, 0x00, 0x02, 0x00, 0x08]),
        ),
        isNull,
      );
    });
  });

  group('PacketCodec STATE_SYNC (0x12) fixtures', () {
    // Player 7 set a trick called "kick" and landed it; player 8 is defending
    // with one letter against player 7's two. Nobody has won.
    final midGame = Uint8List.fromList([
      0x01, // ver
      0x12, // op (STATE_SYNC)
      0x00, 0x07, // senderId = 7
      0x15, // payloadLen = 21 (17 + 4)
      0x02, // phase = defending
      0x00, 0x07, // setterId = 7
      0x00, 0x08, // defenderId = 8
      0x00, 0x07, // firstSetterId = 7
      0x00, 0x00, // winnerId = 0 (nobody)
      0x00, 0x07, // playerA = 7
      0x02, // lettersA = 2
      0x00, 0x08, // playerB = 8
      0x01, // lettersB = 1
      0x01, // flags = trickDeclared
      0x04, // nameLen = 4
      0x6B, 0x69, 0x63, 0x6B, // "kick"
    ]);

    test('the mid-game fixture decodes to exactly the spec values', () {
      final packet = PacketCodec.decode(midGame);
      expect(packet, isA<StateSyncPacket>());

      final sync = packet as StateSyncPacket;
      expect(sync.senderId, equals(7));
      expect(sync.phase, equals(2));
      expect(sync.setterId, equals(7));
      expect(sync.defenderId, equals(8));
      expect(sync.firstSetterId, equals(7));
      expect(sync.winnerId, isNull); // 0 on the wire means "none"
      expect(sync.letters, equals({7: 2, 8: 1}));
      expect(sync.rematchVotes, isEmpty);
      expect(sync.trickDeclared, isTrue);
      expect(sync.trickName, equals('kick'));
    });

    test('encoding that same game reproduces the fixture byte for byte', () {
      final bytes = PacketCodec.encodeStateSync(
        senderId: 7,
        phase: 2,
        setterId: 7,
        defenderId: 8,
        firstSetterId: 7,
        winnerId: null,
        letters: {7: 2, 8: 1},
        rematchVotes: const {},
        trickDeclared: true,
        trickName: 'kick',
      );

      expect(bytes, equals(midGame));
    });

    test(
      'the player pair is written lower-id-first whatever the map order',
      () {
        final ordered = PacketCodec.encodeStateSync(
          senderId: 7,
          phase: 2,
          setterId: 7,
          defenderId: 8,
          firstSetterId: 7,
          winnerId: null,
          letters: {8: 1, 7: 2}, // higher id first
          rematchVotes: const {},
          trickDeclared: true,
          trickName: 'kick',
        );

        expect(ordered, equals(midGame));
      },
    );

    test('decoding is order-agnostic: the pair may arrive either way', () {
      // The same game with player 8 written first, and the vote flags with it.
      final swapped = Uint8List.fromList([
        0x01, 0x12, 0x00, 0x08, 0x11, // header, payloadLen = 17
        0x03, // phase = gameOver
        0x00, 0x08, // setterId = 8
        0x00, 0x07, // defenderId = 7
        0x00, 0x07, // firstSetterId = 7
        0x00, 0x08, // winnerId = 8
        0x00, 0x08, // playerA = 8
        0x00, // lettersA = 0
        0x00, 0x07, // playerB = 7
        0x05, // lettersB = 5
        0x02, // flags = playerA (8) voted
        0x00, // nameLen = 0
      ]);

      final sync = PacketCodec.decode(swapped) as StateSyncPacket;
      expect(sync.letters, equals({7: 5, 8: 0}));
      expect(sync.rematchVotes, equals({8}));
      expect(sync.winnerId, equals(8));
      expect(sync.trickDeclared, isFalse);
      expect(sync.trickName, isNull);
    });

    test('every rematch-vote flag combination round-trips', () {
      for (final votes in [
        <int>{},
        <int>{7},
        <int>{8},
        <int>{7, 8},
      ]) {
        final bytes = PacketCodec.encodeStateSync(
          senderId: 7,
          phase: 3,
          setterId: 7,
          defenderId: 8,
          firstSetterId: 7,
          winnerId: 7,
          letters: {7: 0, 8: 5},
          rematchVotes: votes,
          trickDeclared: false,
          trickName: null,
        );

        final sync = PacketCodec.decode(bytes) as StateSyncPacket;
        expect(sync.rematchVotes, equals(votes), reason: 'votes $votes');
        expect(sync.winnerId, equals(7));
        expect(sync.letters, equals({7: 0, 8: 5}));
      }
    });

    test('an unnamed declared trick is not the same as no trick at all', () {
      final unnamed = PacketCodec.encodeStateSync(
        senderId: 7,
        phase: 1,
        setterId: 7,
        defenderId: 8,
        firstSetterId: 7,
        winnerId: null,
        letters: {7: 0, 8: 0},
        rematchVotes: const {},
        trickDeclared: true,
        trickName: '',
      );
      expect(unnamed[20], equals(0x01)); // flags: declared
      expect(unnamed[21], equals(0x00)); // nameLen: none

      final declared = PacketCodec.decode(unnamed) as StateSyncPacket;
      expect(declared.trickDeclared, isTrue);
      expect(declared.trickName, equals('')); // unnamed, but declared

      final undeclared = PacketCodec.decode(
        PacketCodec.encodeStateSync(
          senderId: 7,
          phase: 1,
          setterId: 7,
          defenderId: 8,
          firstSetterId: 7,
          winnerId: null,
          letters: {7: 0, 8: 0},
          rematchVotes: const {},
          trickDeclared: false,
          trickName: null,
        ),
      ) as StateSyncPacket;
      expect(undeclared.trickDeclared, isFalse);
      expect(undeclared.trickName, isNull);
    });

    test(
      'a name is truncated to the STATE_SYNC ceiling on a UTF-8 boundary',
      () {
        final bytes = PacketCodec.encodeStateSync(
          senderId: 7,
          phase: 1,
          setterId: 7,
          defenderId: 8,
          firstSetterId: 7,
          winnerId: null,
          letters: {7: 0, 8: 0},
          rematchVotes: const {},
          trickDeclared: true,
          trickName: 'é' * 200, // 400 bytes
        );

        expect(bytes[21], lessThanOrEqualTo(PacketCodec.maxSyncTrickNameBytes));
        final sync = PacketCodec.decode(bytes) as StateSyncPacket;
        // 234 bytes would split a character, so 117 whole ones survive.
        expect(sync.trickName, equals('é' * 117));
      },
    );
  });

  group('PacketCodec STATE_SYNC validation drops, never throws', () {
    /// The mid-game fixture with one byte rewritten.
    Uint8List corrupted(int offset, int value) {
      final bytes = Uint8List.fromList([
        0x01,
        0x12,
        0x00,
        0x07,
        0x15,
        0x02,
        0x00,
        0x07,
        0x00,
        0x08,
        0x00,
        0x07,
        0x00,
        0x00,
        0x00,
        0x07,
        0x02,
        0x00,
        0x08,
        0x01,
        0x01,
        0x04,
        0x6B,
        0x69,
        0x63,
        0x6B,
      ]);
      bytes[offset] = value;
      return bytes;
    }

    test('phase 0 and phase 4 are both out of range', () {
      expect(PacketCodec.decode(corrupted(5, 0x00)), isNull);
      expect(PacketCodec.decode(corrupted(5, 0x04)), isNull);
      expect(PacketCodec.decode(corrupted(5, 0xFF)), isNull);
    });

    test('a letter count above 5 is dropped, either player', () {
      expect(PacketCodec.decode(corrupted(16, 0x06)), isNull); // lettersA
      expect(PacketCodec.decode(corrupted(19, 0xFF)), isNull); // lettersB
    });

    test('a nameLen that disagrees with payloadLen is dropped', () {
      expect(PacketCodec.decode(corrupted(21, 0x03)), isNull);
      expect(PacketCodec.decode(corrupted(21, 0x05)), isNull);
    });

    test('a name without the trickDeclared flag is dropped', () {
      expect(PacketCodec.decode(corrupted(20, 0x00)), isNull);
    });

    test('a nameLen over the 234-byte ceiling is dropped', () {
      final bytes = Uint8List(5 + 255);
      final data = ByteData.sublistView(bytes);
      data.setUint8(0, 0x01);
      data.setUint8(1, 0x12);
      data.setUint16(2, 7);
      data.setUint8(4, 255); // payloadLen
      data.setUint8(5, 0x01); // phase = setting
      data.setUint8(20, 0x01); // flags = trickDeclared
      data.setUint8(21, 238); // nameLen = 255 - 17, over the ceiling

      expect(PacketCodec.decode(bytes), isNull);
    });

    test(
      'a truncated STATE_SYNC (17 bytes promised, fewer sent) is dropped',
      () {
        expect(
          PacketCodec.decode(
            Uint8List.fromList([0x01, 0x12, 0x00, 0x07, 0x11, 0x02, 0x00]),
          ),
          isNull,
        );
      },
    );

    test('an invalid UTF-8 name is dropped, not thrown on', () {
      final bytes = Uint8List.fromList([
        0x01, 0x12, 0x00, 0x07, 0x12, // payloadLen = 18 (17 + 1)
        0x01, 0x00, 0x07, 0x00, 0x08, 0x00, 0x07, 0x00, 0x00,
        0x00, 0x07, 0x00, 0x00, 0x08, 0x00, 0x01, 0x01,
        0xC3, // a lone UTF-8 lead byte
      ]);

      expect(() => PacketCodec.decode(bytes), returnsNormally);
      expect(PacketCodec.decode(bytes), isNull);
    });
  });
}
