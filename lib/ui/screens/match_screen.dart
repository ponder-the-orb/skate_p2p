import 'package:flutter/material.dart';

import '../../core/state/app_state.dart';
import '../../core/network/signaling_service.dart';
import '../../core/network/binary_packer.dart';

class MatchScreen extends StatelessWidget {
  final AppState appState;
  final SignalingService signalingService;

  const MatchScreen({
    super.key,
    required this.appState,
    required this.signalingService,
  });

  @override
  Widget build(BuildContext context) {
    // Listen to AppState so this widget rebuilds whenever scores change
    return AnimatedBuilder(
      animation: appState,
      builder: (context, child) {
        final roleString = appState.role == 1 ? 'SETTER' : 'DEFENDER';
        final roomCodeString =
            appState.roomCode?.toString().padLeft(5, '0') ?? '-----';

        return Scaffold(
          appBar: AppBar(
            title: const Text('SKATE P2P MATCH'),
            backgroundColor: Colors.black87,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.exit_to_app),
                tooltip: 'Leave Match',
                onPressed: () {
                  appState.handleLeaveMatch();
                },
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Identity & Status Info
                Card(
                  color: Colors.blueGrey.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'ROOM CODE:',
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              roomCodeString,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.greenAccent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'MY PLAYER ID:',
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${appState.playerId ?? "unknown"}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'ROLE:',
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              roleString,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.amberAccent,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // Scoreboard Card
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        const Text(
                          'SCOREBOARD',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _ScoreColumn(
                              label: 'LOCAL',
                              letters: appState.localLetters,
                            ),
                            const Text(
                              'VS',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            _ScoreColumn(
                              label: 'PEER',
                              letters: appState.peerLetters,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // Action Button: Give Peer a Letter
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () {
                    // Increment local view of peer's letters or fire a test packet
                    final nextLetters = (appState.peerLetters + 1) % 6;

                    // Pack and send binary packet: Opcode 0x02, Sender is the assigned playerId
                    final packet = BinaryPacker.packScoreUpdate(
                      senderId: appState.playerId ?? 0,
                      lettersCount: nextLetters,
                    );

                    signalingService.sendBinary(packet);

		    appState.updatePeerScore(nextLetters);
                  },
                  child: const Text(
                    'GIVE PEER A LETTER (TEST 0x02)',
                    style: TextStyle(fontSize: 16),
                  ),
                ),

                const SizedBox(height: 20),

                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () {
                    appState.handleLeaveMatch();
                  },
                  child: const Text('LEAVE MATCH'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScoreColumn extends StatelessWidget {
  final String label;
  final int letters;

  const _ScoreColumn({required this.label, required this.letters});

  @override
  Widget build(BuildContext context) {
    // S-K-A-T-E spelling helper
    const skateString = "SKATE";
    String displayedLetters = letters == 0
        ? "-"
        : skateString.substring(0, letters);

    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 8),
        Text(
          displayedLetters,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text('$letters/5', style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
