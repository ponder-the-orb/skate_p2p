import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/state/app_state.dart';
import 'core/network/packet_dispatcher.dart';
import 'core/network/network_service.dart';
import 'core/network/binary_packer.dart';

void main() {
  final appState = AppState();
  final dispatcher = PacketDispatcher(appState);
  final network = NetworkService(dispatcher, appState);

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: SkateGameScreen(network: network),
      ),
    ),
  );
}

class SkateGameScreen extends StatelessWidget {
  final NetworkService network;
  const SkateGameScreen({Key? key, required this.network}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // This watches your AppState and rebuilds the screen when variables change
    final state = context.watch<AppState>(); 
    
    // Convert 0-5 into S-K-A-T-E strings
    const skateLetters = ["", "S", "S-K", "S-K-A", "S-K-A-T", "S-K-A-T-E"];

    return Scaffold(
      appBar: AppBar(
        title: Text(state.isConnected ? 'STATUS: CONNECTED' : 'STATUS: OFFLINE'),
        backgroundColor: state.isConnected ? Colors.green[900] : Colors.red[900],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // NETWORK CONTROLS
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () => network.host(8080),
                child: const Text('HOST'),
              ),
              ElevatedButton(
                // Hardcoded local ADB tunnel IP for now
                onPressed: () => network.connect('127.0.0.1', 8080),
                child: const Text('CONNECT'),
              ),
            ],
          ),
          
          const SizedBox(height: 40),

          // SCOREBOARD
          Text('PEER: ${skateLetters[state.peerLetters]}', style: const TextStyle(fontSize: 32, color: Colors.redAccent)),
          const SizedBox(height: 20),
          Text('YOU: ${skateLetters[state.localLetters]}', style: const TextStyle(fontSize: 32, color: Colors.blueAccent)),

          const SizedBox(height: 40),

          // GAME CONTROLS (Only show if connected)
          if (state.isConnected) ...[
            Text(state.isMyTurn ? "YOUR TURN (SETTING)" : "PEER'S TURN (MATCHING)"),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    // Update local state
                    int newScore = state.localLetters + 1;
                    state.updateLocalScore(newScore);
                    
                    // Pack and send across network
                    final packet = BinaryPacker.packScoreUpdate(senderId: 1024, lettersCount: newScore);
                    network.sendPacket(packet);
                  },
                  child: const Text('I BAILED (+1 Letter)'),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Flip turn flag
                    state.setTurnState(!state.isMyTurn);
                    
                    // Pack and send across network
                    final packet = BinaryPacker.packTurnState(senderId: 1024, isMyTurn: !state.isMyTurn);
                    network.sendPacket(packet);
                  },
                  child: const Text('PASS TURN'),
                ),
              ],
            ),
          ]
        ],
      ),
    );
  }
}

