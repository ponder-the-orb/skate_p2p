import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../state/app_state.dart';
import 'packet_codec.dart';

/// Routes validated inbound packets to state changes.
///
/// Branches on byte 0:
/// - 0x01 -> v1 control frame (PROTOCOL.md §5)
/// - any other byte -> legacy v0 format (PROTOCOL.md Appendix A)
///
/// Validation discipline follows PROTOCOL.md §3: malformed input is
/// dropped and logged, never thrown on.
class PacketDispatcher {
  final AppState appState;

  PacketDispatcher(this.appState);

  /// v0 header size in bytes.
  static const int headerSize = 4;

  /// Expected total packet size per known legacy opcode (all v0 packets are fixed
  /// size: header + 1-byte payload).
  static const Map<int, int> _expectedSizes = {
    0x02: 5, // score update
    0x03: 5, // turn state
  };

  void dispatch(dynamic message) {
    if (message is! List<int>) {
      _drop('non-binary message (${message.runtimeType})');
      return;
    }

    final bytes = Uint8List.fromList(message);

    if (bytes.isEmpty) {
      _drop('empty packet');
      return;
    }

    final firstByte = bytes[0];
    if (firstByte == 0x01) {
      // v1 control frame path
      final packet = PacketCodec.decode(bytes);
      if (packet == null) {
        // Drop and log is handled inside decode
        return;
      }

      switch (packet) {
        case JoinedPacket():
          debugPrint(
            '[<<] RECV JOINED (0x02) | '
            'PlayerID: ${packet.playerId} | Room: ${packet.roomCode} | Role: ${packet.role}',
          );
          appState.handleJoined(
            playerId: packet.playerId,
            roomCode: packet.roomCode,
            role: packet.role,
          );
        case PeerJoinedPacket():
          debugPrint('[<<] RECV PEER_JOINED (0x03) | Peer: ${packet.peerId}');
          appState.handlePeerJoined(packet.peerId);
        case PeerLeftPacket():
          debugPrint('[<<] RECV PEER_LEFT (0x04) | Peer: ${packet.peerId}');
          appState.handlePeerLeft(packet.peerId);
        case ErrorPacket():
          debugPrint('[<<] RECV ERROR (0x0F) | Code: ${packet.errorCode}');
          appState.handleRoomError(packet.errorCode);
        case JoinPacket():
          _drop('client received JOIN packet');
      }
      return;
    }

    // Any other first byte -> existing legacy path, unchanged
    if (bytes.length < headerSize) {
      _drop('short packet: ${bytes.length} B < $headerSize B header');
      return;
    }

    final data = ByteData.sublistView(bytes);
    final opcode = data.getUint8(0);

    final expectedSize = _expectedSizes[opcode];
    if (expectedSize == null) {
      _drop('unknown opcode ${_hex(opcode)}');
      return;
    }

    final payloadLen = data.getUint8(3);
    if (bytes.length != headerSize + payloadLen) {
      _drop(
        'length mismatch for ${_hex(opcode)}: '
        'got ${bytes.length} B, header says ${headerSize + payloadLen} B',
      );
      return;
    }
    if (bytes.length != expectedSize) {
      _drop(
        'malformed ${_hex(opcode)}: '
        'got ${bytes.length} B, spec says $expectedSize B',
      );
      return;
    }

    final senderId = data.getUint16(1);

    switch (opcode) {
      case 0x02:
        final lettersCount = data.getUint8(4);
        debugPrint(
          '[<<] RECV Score Update (0x02) | '
          'Sender: $senderId | Letters: $lettersCount',
        );
        appState.updatePeerScore(lettersCount);
      case 0x03:
        final myTurn = data.getUint8(4) == 1;
        debugPrint(
          '[<<] RECV Turn State (0x03) | '
          'Sender: $senderId | IsMyTurn: $myTurn',
        );
        appState.setTurnState(myTurn);
    }
  }

  void _drop(String reason) {
    debugPrint('[-] Dropping packet: $reason');
  }

  String _hex(int opcode) =>
      '0x${opcode.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}
