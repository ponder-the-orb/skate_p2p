import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'binary_packer.dart'; 

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

      // Live fire test packet on connection
      final testPacket = BinaryPacker.packScoreUpdate(senderId: 1024, lettersCount: 3);
      sendBinary(testPacket);

      _channel!.stream.listen(
        (message) {
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

