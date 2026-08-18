import 'dart:typed_data';

class PacketDispatcher {
  static void dispatch(dynamic message) {
    // Ensure we are only dealing with raw bytes
    if (message is! List<int>) {
      print('[-] Dropping non-binary or malformed packet.');
      return;
    }

    // Convert the incoming byte list into a readable buffer
    final byteList = Uint8List.fromList(message);
    final data = ByteData.sublistView(byteList);
    
    final opcode = data.getUint8(0);

    switch (opcode) {
      case 0x01:
        print('[<<] RECV Handshake (0x01)');
        break;
      
      case 0x02:
        final senderId = data.getUint16(1); // Read Bytes 1-2
        final lettersCount = data.getUint8(4); // Read Byte 4
        print('[<<] RECV Score Update (0x02) | Sender: $senderId | Letters: $lettersCount');
        break;
      
      default:
        print('[-] Unknown Opcode: 0x0${opcode.toRadixString(16)}');
    }
  }
}

