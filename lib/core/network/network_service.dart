import 'dart:io';
import 'dart:typed_data';
import 'packet_dispatcher.dart';
import '../state/app_state.dart';

class NetworkService {
  Socket? _socket;
  ServerSocket? _serverSocket; // Added this for hosting
  final PacketDispatcher _dispatcher;
  final AppState _appState;

  NetworkService(this._dispatcher, this._appState);

  // 1. OPEN THE PIPE (Client Mode)
  Future<void> connect(String ipAddress, int port) async {
    try {
      print('[*] Attempting connection to $ipAddress:$port...');
      _socket = await Socket.connect(ipAddress, port);
      
      _appState.setConnectionStatus(true);
      print('[+] Connected to $ipAddress:$port');

      _socket!.listen(
        (Uint8List data) {
          _dispatcher.dispatch(data); // Instantly hand raw bytes to dispatcher
        },
        onError: (error) {
          print('[-] Socket error: $error');
          disconnect();
        },
        onDone: () {
          print('[-] Socket closed by peer.');
          disconnect();
        },
      );
    } catch (e) {
      print('[-] Failed to connect: $e');
      _appState.setConnectionStatus(false);
    }
  }

  // 2. BE THE HOST (Server Mode)
  Future<void> host(int port) async {
    try {
      print('[*] Starting server on port $port...');
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      print('[+] Listening for challenger on port $port...');

      _serverSocket!.listen((Socket clientSocket) {
        print('[+] Challenger connected from ${clientSocket.remoteAddress.address}');
        
        _socket = clientSocket; 
        _appState.setConnectionStatus(true);

        _socket!.listen(
          (Uint8List data) {
            _dispatcher.dispatch(data);
          },
          onError: (error) {
            print('[-] Client socket error: $error');
            disconnect();
          },
          onDone: () {
            print('[-] Client disconnected.');
            disconnect();
          },
        );
      });
    } catch (e) {
      print('[-] Failed to host: $e');
    }
  }

  // 3. SHOOT BYTES ACROSS THE PIPE
  void sendPacket(Uint8List packet) {
    if (_socket != null) {
      _socket!.add(packet);
      print('[>>] Sent ${packet.length} bytes');
    } else {
      print('[-] Cannot send, not connected.');
    }
  }

  // 4. BURN IT DOWN
  void disconnect() {
    _socket?.destroy();
    _socket = null;
    
    _serverSocket?.close();
    _serverSocket = null;
    
    _appState.setConnectionStatus(false);
    print('[-] Disconnected.');
  }
}

