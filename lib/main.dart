// ============================================================================
// FILE: lib/main.dart
// DESCRIPTION: Root entry point and diagnostic terminal interface. Replaces 
// standard UI with a raw event log and live connection state monitor.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'signaling.dart'; // Import our custom low-level networking module

List<CameraDescription> cameras = [];

Future<void> main() async {
  // Ensure Flutter engine bindings are initialized before calling native APIs
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const SkateApp());
}

class SkateApp extends StatelessWidget {
  const SkateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DebugScreen(),
    );
  }
}

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  // Instantiate our network signaling module instance
  final SignalingService _signaling = SignalingService();
  
  // Reactive UI state variables tracking live connection health and packet logs
  String _connectionStatus = 'Initializing...';
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _initSignaling();
  }

  /// Triggers the network connection sequence against our Void laptop's local IP address
  void _initSignaling() {
    // Target IP address of the Void Linux machine running Node.js server.js on port 8080
    const String serverUrl = 'ws://192.168.12.221:8080';

    // Hook into our signaling wrapper with honest, state-driven callbacks
    _signaling.connect(
      serverUrl,
      onStatusChange: (status) {
        // Triggers UI state updates whenever the socket connection changes state
        setState(() {
          _connectionStatus = status;
        });
      },
      onMessage: (data) {
        // Triggers UI state updates when incoming relay packets arrive from peers
        setState(() {
          _logs.add('Incoming: $data');
        });
      },
    );
  }

  @override
  void dispose() {
    // Ensure we clean up and close network sockets when the widget is destroyed
    _signaling.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SKATE_P2P // BACKEND DIAGNOSTICS',
                style: TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              // Dynamically color-codes connection status based on socket state health
              Text(
                'Status: $_connectionStatus',
                style: TextStyle(
                  color: _connectionStatus.contains('Connected') 
                      ? Colors.greenAccent 
                      : (_connectionStatus.contains('Connecting') ? Colors.orangeAccent : Colors.redAccent),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Event Log:',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 5),
              // Retro terminal event log container window
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      return Text(
                        _logs[index],
                        style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

