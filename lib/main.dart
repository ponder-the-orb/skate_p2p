import 'package:flutter/material.dart';
import 'core/state/app_state.dart';
import 'core/network/signaling_service.dart';
import 'core/network/packet_dispatcher.dart';
import 'ui/screens/match_screen.dart';

void main() {
  runApp(const SkateApp());
}

class SkateApp extends StatefulWidget {
  const SkateApp({Key? key}) : super(key: key);

  @override
  State<SkateApp> createState() => _SkateAppState();
}

class _SkateAppState extends State<SkateApp> {
  // Core system instances initialized at the top level of the app
  final AppState _appState = AppState();
  late final SignalingService _signalingService;
  late final PacketDispatcher _packetDispatcher;

  @override
  void initState() {
    super.initState();
    _packetDispatcher = PacketDispatcher(_appState);
    _signalingService = SignalingService();

    // Connect to our local server via ADB reverse tunnel
    _signalingService.connect(
      'ws://127.0.0.1:8080',
      onMessage: (message) {
        // Route incoming raw bytes through our dispatcher
        _packetDispatcher.dispatch(message);
      },
      onStatusChange: (status) {
        print(status);
        if (status == 'Connected') {
          _appState.setConnectionStatus(true);
        } else if (status.contains('Disconnected') || status.contains('Error')) {
          _appState.setConnectionStatus(false);
        }
      },
    );
  }

  @override
  void dispose() {
    _signalingService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'skate_p2p',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.orange,
      ),
      home: MatchScreen(
        appState: _appState,
        signalingService: _signalingService,
      ),
    );
  }
}

