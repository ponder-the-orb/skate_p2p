import 'package:web_socket_channel/web_socket_channel.dart';

class SignalingService {
  WebSocketChannel? _channel;


void connect(
    String url, {
    required Function(dynamic) onMessage,
    required Function(String) onStatusChange,
  }) async {
    WebSocketChannel? channel;
    try {
      onStatusChange('Connecting to $url...');

      channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;

      await channel.ready;
      if (channel != _channel) return; // superseded while connecting

      onStatusChange('Connected');

      channel.stream.listen(
        (message) {
          if (channel != _channel) return; // stale socket — ignore
          onMessage(message);
        },
        onDone: () {
          if (channel != _channel) return; // stale close — ignore
          onStatusChange('Disconnected (Server closed connection)');
        },
        onError: (error) {
          if (channel != _channel) return;
          onStatusChange('Error: $error');
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (channel != null && channel != _channel) return;
      onStatusChange('Connection Failed: $e');
    }
  }
}
