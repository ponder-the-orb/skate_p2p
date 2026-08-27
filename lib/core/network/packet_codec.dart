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

class PacketCodec {
  /// Header size for v1 packets
  static const int headerSize = 5;

  /// Expected payload lengths for known control opcodes
  static const Map<int, int> _expectedPayloadLengths = {
    0x01: 4, // JOIN
    0x02: 7, // JOINED
    0x03: 2, // PEER_JOINED
    0x04: 2, // PEER_LEFT
    0x0F: 1, // ERROR
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

  /// Decodes an incoming v1 control packet.
  /// Validates according to PROTOCOL.md §3:
  /// - returns null if the packet is malformed or not a control packet.
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

    final expectedPayloadLen = _expectedPayloadLengths[opcode];
    if (expectedPayloadLen == null) {
      debugPrint(
        '[-] Dropping v1 packet: unknown opcode 0x${opcode.toRadixString(16).padLeft(2, '0').toUpperCase()}',
      );
      return null;
    }

    if (payloadLen != expectedPayloadLen) {
      debugPrint(
        '[-] Dropping v1 packet: malformed opcode 0x${opcode.toRadixString(16).padLeft(2, '0').toUpperCase()}: got payload len $payloadLen, spec says $expectedPayloadLen',
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
        default:
          return null;
      }
    } catch (e) {
      debugPrint('[-] Error decoding v1 packet body: $e');
      return null;
    }
  }
}
