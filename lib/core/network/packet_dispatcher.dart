import 'dart:typed_data';
import '../state/app_state.dart'; 

class PacketDispatcher {
  final AppState appState;

  PacketDispatcher(this.appState);

  void dispatch(dynamic message) {
    if (message is! List<int>) {
      print('[-] Dropping non-binary or malformed packet.');
      return;
    }

    final byteList = Uint8List.fromList(message);
    final data = ByteData.sublistView(byteList);

    final opcode = data.getUint8(0);

    switch (opcode) {
      case 0x01:
        print('[<<] RECV Handshake (0x01)');
        break;

      case 0x02: {
        final senderId = data.getUint16(1);
        final lettersCount = data.getUint8(4);
        print('[<<] RECV Score Update (0x02) | Sender: $senderId | Letters: $lettersCount');

        appState.updatePeerScore(lettersCount);
        break;
      }

      case 0x03: {
        final senderId = data.getUint16(1);
        final turnFlag = data.getUint8(4);
        final myTurn = turnFlag == 1;
        print('[<<] RECV Turn State (0x03) | Sender: $senderId | IsMyTurn: $myTurn');

        appState.setTurnState(myTurn);
        break;
      }

      default:
        print('[-] Unknown Opcode: 0x0${opcode.toRadixString(16)}');
    }
  }
}

