// ============================================================================
// FILE: lib/signaling.dart
// DESCRIPTION: Encapsulates the WebSocket client network layer. Manages the 
// TCP handshake, live stream subscriptions, and JSON serialization.
// ============================================================================

import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class SignalingService {
  // The core WebSocket communication channel wrapper provided by package:web_socket_channel
  WebSocketChannel? _channel;

  /// Establishes an asynchronous TCP connection to the target signaling server URL.
  /// Passes state updates and incoming data back to the UI via callbacks.
  void connect(
    String url, {
    required Function(dynamic) onMessage,
    required Function(String) onStatusChange,
  }) async {
    try {
      // Notify the caller that we are attempting to open a socket connection
      onStatusChange('Connecting to $url...');
      
      // Parse the URI string and initialize the socket connection channel
      _channel = WebSocketChannel.connect(Uri.parse(url));
      
      // Await the underlying network future to ensure the connection is fully negotiated
      await _channel!.ready;
      
      // Connection successfully opened
      onStatusChange('Connected');

      // Subscribe to the incoming data stream from the WebSocket server.
      // This is an event-driven stream: whenever the server broadcasts data, 
      // the .listen() callback executes asynchronously.
      _channel!.stream.listen(
        (message) {
          // Triggered when a raw packet payload arrives from the network
          onMessage(message);
        },
        onDone: () {
          // Triggered gracefully if the remote server closes the connection socket
          onStatusChange('Disconnected (Server closed connection)');
        },
        onError: (error) {
          // Triggered if a network socket error occurs mid-stream
          onStatusChange('Error: $error');
        },
        cancelOnError: true,
      );
    } catch (e) {
      // Catches DNS lookup failures, connection refusals, or invalid URIs
      onStatusChange('Connection Failed: $e');
    }
  }

  /// Encodes a Map into a JSON string and pushes it down the WebSocket sink (outbound).
  void send(Map<String, dynamic> data) {
    if (_channel != null) {
      // jsonEncode converts Dart maps into standard JSON string wire format
      _channel!.sink.add(jsonEncode(data));
    }
  }

  /// Gracefully tears down the WebSocket channel and releases network resources.
  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}

