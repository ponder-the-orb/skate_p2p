import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
// IMPORTANT: Update this import path to point to your new file!
import 'binary_packer.dart'; 
import 'packet_dispatcher.dart'; 

class SignalingService {
  WebSocketChannel? _channel;

  void connect(
    String url, {
    required Function(dynamic) onMessage,
    required Function(String) onStatusChange,
  }) async {
    try {
      onStatusChange('Connecting to $url...');

      _channel = WebSocketChannel.connect(Uri.parse(url));

      await _channel!.ready;

      onStatusChange('Connected');

      // 🔥 THE LIVE FIRE TRIGGER 🔥
      // The second we connect, pack a binary S-K-A-T-E packet and fire it.
      final testPacket = BinaryPacker.packScoreUpdate(senderId: 1024, lettersCount: 3);
      sendBinary(testPacket);
      // 🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥

      _channel!.stream.listen(
        (message) {

	// FIRE THE DISPATCHER
	PacketDispatcher.dispatch(message);

	// Keep your original callback if the UI needs it later
          onMessage(message);
        },
        onDone: () {
          onStatusChange('Disconnected (Server closed connection)');
        },
        onError: (error) {
          onStatusChange('Error: $error');
        },
        cancelOnError: true,
      );
    } catch (e) {
      onStatusChange('Connection Failed: $e');
    }
  }

  // OUR NEW BARE-METAL SEND METHOD
  void sendBinary(Uint8List data) {
    if (_channel != null) {
      _channel!.sink.add(data);
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}

