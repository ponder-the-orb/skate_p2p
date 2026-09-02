import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

sealed class V1Packet {
  final int opcode;
  final int senderId;

  V1Packet({required this.opcode, required this.senderId});
}

class JoinPacket extends V1Packet {
  final int roomCode;

  JoinPacket({required super.senderId, required this.roomCode})
    : super(opcode: 0x01);
}

class JoinedPacket extends V1Packet {
  final int playerId;
  final int roomCode;
  final int role;

  JoinedPacket({
    required super.senderId,
    required this.playerId,
    required this.roomCode,
    required this.role,
  }) : super(opcode: 0x02);
}

class PeerJoinedPacket extends V1Packet {
  final int peerId;

  PeerJoinedPacket({required super.senderId, required this.peerId})
    : super(opcode: 0x03);
}

class PeerLeftPacket extends V1Packet {
  final int peerId;

  PeerLeftPacket({required super.senderId, required this.peerId})
    : super(opcode: 0x04);
}

/// Control opcode `0x05` — the peer's socket dropped, but the room is in
/// reconnect grace for [graceSeconds]. The game is NOT abandoned.
class PeerDisconnectedPacket extends V1Packet {
  final int peerId;
  final int graceSeconds;

  PeerDisconnectedPacket({
    required super.senderId,
    required this.peerId,
    required this.graceSeconds,
  }) : super(opcode: 0x05);
}

/// Control opcode `0x06` — the graced room is whole again. Sent to BOTH.
class PeerReconnectedPacket extends V1Packet {
  final int peerId;

  PeerReconnectedPacket({required super.senderId, required this.peerId})
    : super(opcode: 0x06);
}

class ErrorPacket extends V1Packet {
  final int errorCode;

  ErrorPacket({required super.senderId, required this.errorCode})
    : super(opcode: 0x0F);
}

/// Game opcode `0x10` — the setter declares the trick.
/// An empty [name] is legal and means "unnamed trick" (PROTOCOL.md §6).
class TrickSetPacket extends V1Packet {
  final String name;

  TrickSetPacket({required super.senderId, required this.name})
    : super(opcode: 0x10);
}

/// Game opcode `0x11` — the attempting player reports their own result.
class AttemptResultPacket extends V1Packet {
  final bool landed;

  AttemptResultPacket({required super.senderId, required this.landed})
    : super(opcode: 0x11);
}

/// Game opcode `0x12` — the full game-state snapshot the survivor sends to a
/// rejoining peer (PROTOCOL.md §6). Carries facts only: the receiver rebuilds
/// its engine snapshot from these, it does not replay events.
///
/// [winnerId] is null when nobody has won (the wire's `0` — playerIds are
/// never 0). [trickName] is null when no trick is declared; an empty string is
/// the legal "unnamed trick".
class StateSyncPacket extends V1Packet {
  final int phase; // 1 setting · 2 defending · 3 gameOver
  final int setterId;
  final int defenderId;
  final int firstSetterId;
  final int? winnerId;
  final Map<int, int> letters;
  final Set<int> rematchVotes;
  final bool trickDeclared;
  final String? trickName;

  StateSyncPacket({
    required super.senderId,
    required this.phase,
    required this.setterId,
    required this.defenderId,
    required this.firstSetterId,
    required this.winnerId,
    required this.letters,
    required this.rematchVotes,
    required this.trickDeclared,
    required this.trickName,
  }) : super(opcode: 0x12);
}

/// Game opcode `0x13` — a vote for a rematch. Payload is empty.
class RematchPacket extends V1Packet {
  RematchPacket({required super.senderId}) : super(opcode: 0x13);
}

class PacketCodec {
  /// Header size for v1 packets
  static const int headerSize = 5;

  /// Longest trick name the wire can carry: `nameLen` is a uint8 capped at 254
  /// by PROTOCOL.md §6.
  static const int maxTrickNameBytes = 254;

  /// `STATE_SYNC` carries 17 fixed bytes before its `nameLen`, so its name
  /// ceiling is lower than `TRICK_SET`'s (PROTOCOL.md §6).
  static const int maxSyncTrickNameBytes = 234;

  /// Fixed part of a `STATE_SYNC` payload: everything up to and including
  /// `nameLen`.
  static const int _stateSyncFixedLen = 17;

  /// Expected payload lengths for opcodes whose payload is a fixed size.
  /// `TRICK_SET` (0x10) is variable-length and validated separately.
  static const Map<int, int> _expectedPayloadLengths = {
    0x01: 4, // JOIN
    0x02: 7, // JOINED
    0x03: 2, // PEER_JOINED
    0x04: 2, // PEER_LEFT
    0x05: 4, // PEER_DISCONNECTED
    0x06: 2, // PEER_RECONNECTED
    0x0F: 1, // ERROR
    0x11: 1, // ATTEMPT_RESULT
    0x13: 0, // REMATCH
  };

  /// Encodes a JOIN packet
  static Uint8List encodeJoin({required int roomCode, int senderId = 0x0000}) {
    final bytes = Uint8List(headerSize + 4);
    final data = ByteData.sublistView(bytes);

    data.setUint8(0, 0x01); // version
    data.setUint8(1, 0x01); // opcode
    data.setUint16(2, senderId); // senderId
    data.setUint8(4, 4); // payloadLen
    data.setUint32(5, roomCode); // roomCode

    return bytes;
  }

  /// Encodes a TRICK_SET packet. An empty [name] encodes `nameLen == 0`,
  /// the wire's "unnamed trick".
  static Uint8List encodeTrickSet({
    required int senderId,
    required String name,
  }) {
    final nameBytes = _truncateUtf8(utf8.encode(name), maxTrickNameBytes);

    final bytes = Uint8List(headerSize + 1 + nameBytes.length);
    final data = ByteData.sublistView(bytes);

    data.setUint8(0, 0x01); // version
    data.setUint8(1, 0x10); // opcode
    data.setUint16(2, senderId); // senderId
    data.setUint8(4, 1 + nameBytes.length); // payloadLen
    data.setUint8(5, nameBytes.length); // nameLen
    bytes.setRange(6, 6 + nameBytes.length, nameBytes);

    return bytes;
  }

  /// Encodes an ATTEMPT_RESULT packet: `0x00` bailed, `0x01` landed.
  static Uint8List encodeAttemptResult({
    required int senderId,
    required bool landed,
  }) {
    final bytes = Uint8List(headerSize + 1);
    final data = ByteData.sublistView(bytes);

    data.setUint8(0, 0x01); // version
    data.setUint8(1, 0x11); // opcode
    data.setUint16(2, senderId); // senderId
    data.setUint8(4, 1); // payloadLen
    data.setUint8(5, landed ? 0x01 : 0x00); // result

    return bytes;
  }

  /// Encodes a STATE_SYNC packet — the whole game in 17 bytes plus a name.
  ///
  /// [letters] must hold exactly the two players; the pair is written
  /// lower-id-first so the same game always produces the same bytes. Pass
  /// `winnerId: 0` (or null) for "nobody has won yet", and a null [trickName]
  /// when no trick is declared.
  static Uint8List encodeStateSync({
    required int senderId,
    required int phase,
    required int setterId,
    required int defenderId,
    required int firstSetterId,
    required int? winnerId,
    required Map<int, int> letters,
    required Set<int> rematchVotes,
    required bool trickDeclared,
    required String? trickName,
  }) {
    final ids = letters.keys.toList()..sort();
    final playerA = ids.isNotEmpty ? ids.first : 0;
    final playerB = ids.length > 1 ? ids.last : 0;

    final nameBytes = trickDeclared
        ? _truncateUtf8(utf8.encode(trickName ?? ''), maxSyncTrickNameBytes)
        : Uint8List(0);

    var flags = 0;
    if (trickDeclared) flags |= 0x01;
    if (rematchVotes.contains(playerA)) flags |= 0x02;
    if (rematchVotes.contains(playerB)) flags |= 0x04;

    final bytes = Uint8List(headerSize + _stateSyncFixedLen + nameBytes.length);
    final data = ByteData.sublistView(bytes);

    data.setUint8(0, 0x01); // version
    data.setUint8(1, 0x12); // opcode
    data.setUint16(2, senderId); // senderId
    data.setUint8(4, _stateSyncFixedLen + nameBytes.length); // payloadLen
    data.setUint8(5, phase);
    data.setUint16(6, setterId);
    data.setUint16(8, defenderId);
    data.setUint16(10, firstSetterId);
    data.setUint16(12, winnerId ?? 0);
    data.setUint16(14, playerA);
    data.setUint8(16, letters[playerA] ?? 0);
    data.setUint16(17, playerB);
    data.setUint8(19, letters[playerB] ?? 0);
    data.setUint8(20, flags);
    data.setUint8(21, nameBytes.length);
    bytes.setRange(22, 22 + nameBytes.length, nameBytes);

    return bytes;
  }

  /// Encodes a REMATCH packet (no payload).
  static Uint8List encodeRematch({required int senderId}) {
    final bytes = Uint8List(headerSize);
    final data = ByteData.sublistView(bytes);

    data.setUint8(0, 0x01); // version
    data.setUint8(1, 0x13); // opcode
    data.setUint16(2, senderId); // senderId
    data.setUint8(4, 0); // payloadLen

    return bytes;
  }

  /// Decodes an incoming v1 packet (control or game).
  /// Validates according to PROTOCOL.md §3:
  /// - returns null if the packet is malformed or the opcode is unknown.
  /// - never throws an exception.
  static V1Packet? decode(Uint8List bytes) {
    if (bytes.length < headerSize) {
      debugPrint(
        '[-] Dropping v1 packet: short packet: ${bytes.length} B < $headerSize B header',
      );
      return null;
    }

    final data = ByteData.sublistView(bytes);
    final version = data.getUint8(0);
    if (version != 0x01) {
      debugPrint('[-] Dropping v1 packet: unsupported version $version');
      return null;
    }

    final opcode = data.getUint8(1);
    final senderId = data.getUint16(2);
    final payloadLen = data.getUint8(4);

    if (bytes.length != headerSize + payloadLen) {
      debugPrint(
        '[-] Dropping v1 packet: length mismatch: got ${bytes.length} B, header says ${headerSize + payloadLen} B',
      );
      return null;
    }

    // TRICK_SET is the one variable-length payload: 1 length byte + the name.
    if (opcode == 0x10) {
      if (payloadLen < 1) {
        debugPrint(
          '[-] Dropping v1 packet: malformed opcode 0x10: payload must carry a nameLen byte',
        );
        return null;
      }
      final nameLen = data.getUint8(5);
      if (nameLen != payloadLen - 1) {
        debugPrint(
          '[-] Dropping v1 packet: malformed opcode 0x10: nameLen $nameLen does not match payload len $payloadLen',
        );
        return null;
      }
      try {
        final name = utf8.decode(bytes.sublist(6, 6 + nameLen));
        return TrickSetPacket(senderId: senderId, name: name);
      } catch (e) {
        debugPrint('[-] Dropping v1 packet: TRICK_SET name is not valid UTF-8');
        return null;
      }
    }

    // STATE_SYNC is the other variable-length payload: 17 fixed bytes, the
    // last of which is `nameLen`, then the name. Every field is range-checked
    // before it reaches the engine — a malformed snapshot is dropped, never
    // installed (PROTOCOL.md §3, §6).
    if (opcode == 0x12) {
      if (payloadLen < _stateSyncFixedLen) {
        debugPrint(
          '[-] Dropping v1 packet: malformed opcode 0x12: payload $payloadLen B < $_stateSyncFixedLen B',
        );
        return null;
      }
      final nameLen = data.getUint8(21);
      if (nameLen != payloadLen - _stateSyncFixedLen) {
        debugPrint(
          '[-] Dropping v1 packet: malformed opcode 0x12: nameLen $nameLen does not match payload len $payloadLen',
        );
        return null;
      }
      if (nameLen > maxSyncTrickNameBytes) {
        debugPrint(
          '[-] Dropping v1 packet: malformed opcode 0x12: nameLen $nameLen exceeds $maxSyncTrickNameBytes',
        );
        return null;
      }

      final phase = data.getUint8(5);
      if (phase < 1 || phase > 3) {
        debugPrint(
          '[-] Dropping v1 packet: malformed opcode 0x12: phase $phase is not 1, 2 or 3',
        );
        return null;
      }

      final playerA = data.getUint16(14);
      final lettersA = data.getUint8(16);
      final playerB = data.getUint16(17);
      final lettersB = data.getUint8(19);
      if (lettersA > 5 || lettersB > 5) {
        debugPrint(
          '[-] Dropping v1 packet: malformed opcode 0x12: letters out of range ($lettersA, $lettersB)',
        );
        return null;
      }

      final flags = data.getUint8(20);
      final trickDeclared = (flags & 0x01) != 0;
      if (!trickDeclared && nameLen > 0) {
        debugPrint(
          '[-] Dropping v1 packet: malformed opcode 0x12: a name without the trickDeclared flag',
        );
        return null;
      }

      final String? trickName;
      if (trickDeclared) {
        try {
          trickName = utf8.decode(bytes.sublist(22, 22 + nameLen));
        } catch (e) {
          debugPrint(
            '[-] Dropping v1 packet: STATE_SYNC name is not valid UTF-8',
          );
          return null;
        }
      } else {
        trickName = null;
      }

      final winnerId = data.getUint16(12);
      final votes = <int>{
        if ((flags & 0x02) != 0) playerA,
        if ((flags & 0x04) != 0) playerB,
      };

      return StateSyncPacket(
        senderId: senderId,
        phase: phase,
        setterId: data.getUint16(6),
        defenderId: data.getUint16(8),
        firstSetterId: data.getUint16(10),
        winnerId: winnerId == 0 ? null : winnerId,
        letters: {playerA: lettersA, playerB: lettersB},
        rematchVotes: votes,
        trickDeclared: trickDeclared,
        trickName: trickName,
      );
    }

    final expectedPayloadLen = _expectedPayloadLengths[opcode];
    if (expectedPayloadLen == null) {
      debugPrint('[-] Dropping v1 packet: unknown opcode ${_hex(opcode)}');
      return null;
    }

    if (payloadLen != expectedPayloadLen) {
      debugPrint(
        '[-] Dropping v1 packet: malformed opcode ${_hex(opcode)}: got payload len $payloadLen, spec says $expectedPayloadLen',
      );
      return null;
    }

    // Now extract payloads based on opcode
    try {
      switch (opcode) {
        case 0x01:
          final roomCode = data.getUint32(5);
          return JoinPacket(senderId: senderId, roomCode: roomCode);
        case 0x02:
          final playerId = data.getUint16(5);
          final roomCode = data.getUint32(7);
          final role = data.getUint8(11);
          return JoinedPacket(
            senderId: senderId,
            playerId: playerId,
            roomCode: roomCode,
            role: role,
          );
        case 0x03:
          final peerId = data.getUint16(5);
          return PeerJoinedPacket(senderId: senderId, peerId: peerId);
        case 0x04:
          final peerId = data.getUint16(5);
          return PeerLeftPacket(senderId: senderId, peerId: peerId);
        case 0x05:
          final peerId = data.getUint16(5);
          final graceSeconds = data.getUint16(7);
          return PeerDisconnectedPacket(
            senderId: senderId,
            peerId: peerId,
            graceSeconds: graceSeconds,
          );
        case 0x06:
          final peerId = data.getUint16(5);
          return PeerReconnectedPacket(senderId: senderId, peerId: peerId);
        case 0x0F:
          final errorCode = data.getUint8(5);
          return ErrorPacket(senderId: senderId, errorCode: errorCode);
        case 0x11:
          final result = data.getUint8(5);
          if (result != 0x00 && result != 0x01) {
            debugPrint(
              '[-] Dropping v1 packet: malformed opcode 0x11: result byte $result is neither bail (0x00) nor land (0x01)',
            );
            return null;
          }
          return AttemptResultPacket(
            senderId: senderId,
            landed: result == 0x01,
          );
        case 0x13:
          return RematchPacket(senderId: senderId);
        default:
          return null;
      }
    } catch (e) {
      debugPrint('[-] Error decoding v1 packet body: $e');
      return null;
    }
  }

  /// Cuts [bytes] down to at most [limit] bytes without splitting a multi-byte
  /// UTF-8 sequence (which would make the name undecodable on the far side).
  static Uint8List _truncateUtf8(List<int> bytes, int limit) {
    if (bytes.length <= limit) return Uint8List.fromList(bytes);
    var end = limit;
    // 0b10xxxxxx is a continuation byte: back up until we land on a boundary.
    while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
      end--;
    }
    return Uint8List.fromList(bytes.sublist(0, end));
  }

  static String _hex(int opcode) =>
      '0x${opcode.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}
