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

  /// Expected payload lengths for opcodes whose payload is a fixed size.
  /// `TRICK_SET` (0x10) is variable-length and validated separately.
  static const Map<int, int> _expectedPayloadLengths = {
    0x01: 4, // JOIN
    0x02: 7, // JOINED
    0x03: 2, // PEER_JOINED
    0x04: 2, // PEER_LEFT
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
