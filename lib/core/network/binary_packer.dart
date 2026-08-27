import 'dart:typed_data';

/// Builds outbound packets in the legacy v0 format
/// (PROTOCOL.md Appendix A): `[opcode:1][senderId:2][payloadLen:1]` + payload.
class BinaryPacker {
  // OPCODE 0x02: S-K-A-T-E Score Update (Total: 5 bytes)
  static Uint8List packScoreUpdate({
    required int senderId,
    required int lettersCount,
  }) {
    final data = ByteData(5);
    data.setUint8(0, 0x02); // Byte 0: Opcode
    data.setUint16(1, senderId); // Byte 1-2: Sender ID
    data.setUint8(3, 0x01); // Byte 3: Payload Length (1 byte)
    data.setUint8(4, lettersCount); // Byte 4: Payload Data (0 to 5)
    return data.buffer.asUint8List();
  }

  // OPCODE 0x03: Turn State Update (Total: 5 bytes)
  // Payload: 1 byte (1 = My turn/Setter, 0 = Peer's turn/Challenger)
  static Uint8List packTurnState({
    required int senderId,
    required bool isMyTurn,
  }) {
    final data = ByteData(5);
    data.setUint8(0, 0x03); // Byte 0: Opcode
    data.setUint16(1, senderId); // Byte 1-2: Sender ID
    data.setUint8(3, 0x01); // Byte 3: Payload Length (1 byte)
    data.setUint8(4, isMyTurn ? 1 : 0); // Byte 4: Turn flag
    return data.buffer.asUint8List();
  }
}
