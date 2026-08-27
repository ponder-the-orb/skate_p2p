import 'package:flutter/foundation.dart';

import '../state/app_state.dart';

/// Routes validated inbound packets to state changes.
///
/// Speaks the legacy v0 format (PROTOCOL.md Appendix A):
/// 4-byte header `[opcode:1][senderId:2][payloadLen:1]` + payload.
/// Validation discipline follows PROTOCOL.md §3: malformed input is
/// dropped and logged, never thrown on.
class PacketDispatcher {
  final AppState appState;

  PacketDispatcher(this.appState);

  /// v0 header size in bytes.
  static const int headerSize = 4;

  /// Expected total packet size per known opcode (all v0 packets are fixed
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
