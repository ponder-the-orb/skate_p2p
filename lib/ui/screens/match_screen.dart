import 'package:flutter/material.dart';

import '../../core/state/app_state.dart';
import '../../game/game_engine.dart';

/// Functional match UI: everything is derived from `appState.game` plus the
/// local `playerId`. Nothing about whose turn it is comes off the wire
/// (ADR-003). Visual polish is T2.3's job.
class MatchScreen extends StatefulWidget {
  final AppState appState;

  const MatchScreen({super.key, required this.appState});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  final TextEditingController _trickController = TextEditingController();

  @override
  void dispose() {
    _trickController.dispose();
    super.dispose();
  }

  void _submitTrick() {
    widget.appState.setTrick(_trickController.text.trim());
    _trickController.clear();
  }

  /// "You set" / "They set" / "Match their trick" / "Waiting…"
  String _phaseText(GameState game, int? myId) {
    switch (game.phase) {
      case GamePhase.setting:
        return game.setterId == myId ? 'You set' : 'They set';
      case GamePhase.defending:
        return game.defenderId == myId ? 'Match their trick' : 'Waiting…';
      case GamePhase.gameOver:
        return game.winnerId == myId ? 'You win' : 'You lose';
      case GamePhase.abandoned:
        return 'Opponent left';
      case GamePhase.lobby:
        return 'Waiting…';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, child) {
        final game = widget.appState.game;
        final myId = widget.appState.playerId;
        final peerId = widget.appState.peerId;
        final roomCodeString =
            widget.appState.roomCode?.toString().padLeft(5, '0') ?? '-----';

        // The setter attempts their own trick once they have declared it; the
        // defender attempts in the defending phase. Exactly one player has a
        // button at any moment.
        final isMySetTurn =
            game.phase == GamePhase.setting &&
            game.setterId == myId &&
            !game.trickDeclared;
        final isMyAttempt =
            (game.phase == GamePhase.setting &&
                game.setterId == myId &&
                game.trickDeclared) ||
            (game.phase == GamePhase.defending && game.defenderId == myId);

        return Scaffold(
          appBar: AppBar(
            title: const Text('SKATE P2P MATCH'),
            actions: [
              IconButton(
                icon: const Icon(Icons.exit_to_app),
                tooltip: 'Leave Match',
                onPressed: widget.appState.handleLeaveMatch,
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Room $roomCodeString · you are player ${myId ?? "?"}'),
                  const SizedBox(height: 24),

                  // Letters, per player, straight from the engine.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _LetterColumn(
                        label: 'YOU',
                        letters: game.letters[myId] ?? 0,
                      ),
                      _LetterColumn(
                        label: 'THEM',
                        letters: game.letters[peerId] ?? 0,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Text(
                    _phaseText(game, myId),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20),
                  ),
                  if (game.trickDeclared) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Trick: ${_trickLabel(game.currentTrickName)}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Setter declaring a trick. Empty field = unnamed trick.
                  if (isMySetTurn) ...[
                    TextField(
                      controller: _trickController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Trick name (optional)',
                      ),
                      onSubmitted: (_) => _submitTrick(),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _submitTrick,
                      child: const Text('SET'),
                    ),
                  ],

                  // The attempting player reports their own result.
                  if (isMyAttempt) ...[
                    ElevatedButton(
                      onPressed: () => widget.appState.reportResult(true),
                      child: const Text('LANDED'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => widget.appState.reportResult(false),
                      child: const Text('BAILED'),
                    ),
                  ],

                  if (game.phase == GamePhase.gameOver) ...[
                    Text(
                      game.winnerId == myId
                          ? 'Game over — you win.'
                          : 'Game over — you lose.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: widget.appState.voteRematch,
                      child: Text(
                        myId != null && game.rematchVotes.contains(myId)
                            ? 'WAITING FOR REMATCH…'
                            : 'REMATCH',
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: widget.appState.handleLeaveMatch,
                    child: const Text('LEAVE MATCH'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _trickLabel(String? name) =>
      (name == null || name.isEmpty) ? '(unnamed)' : name;
}

class _LetterColumn extends StatelessWidget {
  final String label;
  final int letters;

  const _LetterColumn({required this.label, required this.letters});

  @override
  Widget build(BuildContext context) {
    // S-K-A-T-E spelling helper
    const skateString = 'SKATE';
    final displayedLetters = letters == 0
        ? '-'
        : skateString.substring(0, letters.clamp(0, 5));

    return Column(
      children: [
        Text(label),
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
        Text('$letters/5'),
      ],
    );
  }
}
