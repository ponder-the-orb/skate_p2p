import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'signaling.dart'; 

List<CameraDescription> cameras = [];

Future<void> main() async {
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
  final SignalingService _signaling = SignalingService();
  
  String _connectionStatus = 'Initializing...';
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _initSignaling();
  }

  void _initSignaling() {
    const String serverUrl = 'ws://127.0.0.1:8080';

    _signaling.connect(
      serverUrl,
      onStatusChange: (status) {
        setState(() {
          _connectionStatus = status;
        });
      },
      onMessage: (data) {
        setState(() {
          _logs.add('Incoming: $data');
        });
      },
    );
  }

  @override
  void dispose() {
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

