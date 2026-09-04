import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/state/app_state.dart';
import '../../game/game_engine.dart';
import '../clip_environment.dart';
import '../data/trick_presets.dart';
import '../widgets/attempt_timer.dart';
import 'record_screen.dart';

// Match palette. Dark, high contrast, one acid accent for "your move" and one
// red for "you ate it". Deliberately local to this screen.
const Color _bg = Color(0xFF0E1014);
const Color _surface = Color(0xFF191D25);
const Color _line = Color(0xFF2B313C);
const Color _accent = Color(0xFFD8FF3E);
const Color _danger = Color(0xFFFF5C5C);
const Color _muted = Color(0xFF8B94A5);
const Color _text = Color(0xFFF3F5F9);

/// Reconnect grace, survivor side. The countdown is cosmetic: it runs off the
/// `graceSeconds` the server announced (PROTOCOL.md §5) and decides nothing.
/// PEER_LEFT remains the sole authority on a game actually ending, which is
/// why zero reads as "any moment" rather than "over".
String reconnectingLabel(int seconds) => 'Opponent reconnecting… ${seconds}s';
const String reconnectingImminentLabel = 'Opponent reconnecting… any moment…';

/// Reconnect grace, rejoiner side: waiting for the survivor's STATE_SYNC.
const String restoringLabel = 'Restoring game…';

/// The entry into the clips flow. Offered only to the player who is actually
/// attempting something (states 2 and 4), and only where a camera exists.
const String recordEntryLabel = 'FILM IT';

/// The match screen.
///
/// Everything drawn here is derived from `appState.game` plus the local
/// `playerId`/`peerId`. No rules live in this file (ARCHITECTURE.md §3) and
/// nothing about whose turn it is comes off the wire (ADR-003).
///
/// The states it renders, in ticket order:
///   1. setting, I'm setter, nothing declared → preset chips + field + SET
///   2. setting, I'm setter, declared         → my trick + LANDED / BAILED
///   3. setting, peer is setter               → waiting, peer is up
///   4. defending, I'm defender               → their trick, huge + LANDED / BAILED
///   5. defending, peer defends               → waiting
///   6. gameOver                              → full-screen WIN / LOSE + rematch
///   7. abandoned                             → the lobby-return flow handles it
class MatchScreen extends StatefulWidget {
  final AppState appState;

  const MatchScreen({super.key, required this.appState});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  final TextEditingController _trickController = TextEditingController();

  /// Whether this device can film at all. Starts false and only ever becomes
  /// true, so a device without a camera — the Producer's Linux desktop, a test
  /// VM — simply never renders the entry. Nothing here can throw.
  bool _cameraAvailable = false;

  @override
  void initState() {
    super.initState();
    CameraAvailability.isAvailable.then((available) {
      if (!mounted || !available) return;
      setState(() => _cameraAvailable = true);
    });
  }

  @override
  void dispose() {
    _trickController.dispose();
    super.dispose();
  }

  /// Opens the clips flow. Local only: it reports nothing, sends nothing, and
  /// the match root stays authoritative for anything the network decides while
  /// the player is in there (ADR-008).
  void _openRecorder(String? trickName) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => RecordScreen(trickName: trickName),
      ),
    );
  }

  void _submitTrick() {
    widget.appState.setTrick(_trickController.text.trim());
    _trickController.clear();
  }

  /// A preset chip only fills the field — it never declares. SET stays the
  /// single commit path, and the filled name is still editable.
  void _fillTrick(String name) {
    _trickController.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, child) {
        final app = widget.appState;

        // The rejoiner has its seat back but no game yet: there is nothing
        // truthful to draw until the survivor's STATE_SYNC lands.
        if (app.awaitingSync) {
          return const _RestoringScreen();
        }

        final game = app.game;
        final myId = app.playerId;
        final peerId = app.peerId;

        final iAmSetter = myId != null && game.setterId == myId;
        final iAmDefender = myId != null && game.defenderId == myId;

        // Exactly one player has a button at any moment (ARCHITECTURE.md §4).
        final mySetTurn =
            game.phase == GamePhase.setting && iAmSetter && !game.trickDeclared;
        final myAttempt =
            (game.phase == GamePhase.setting &&
                iAmSetter &&
                game.trickDeclared) ||
            (game.phase == GamePhase.defending && iAmDefender);
        final iAmUp = mySetTurn || myAttempt;

        final inPlay =
            game.phase == GamePhase.setting ||
            game.phase == GamePhase.defending;

        final myLetters = game.letters[myId] ?? 0;
        final peerLetters = game.letters[peerId] ?? 0;

        return Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(
                      roomCode: app.roomCode,
                      onLeave: app.handleLeaveMatch,
                    ),
                    if (app.peerDisconnected)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                        child: _ReconnectBanner(
                          key: ValueKey('grace-${app.graceSeconds}'),
                          seconds: app.graceSeconds,
                        ),
                      ),
                    _Scoreboard(
                      myLetters: myLetters,
                      peerLetters: peerLetters,
                      turn: !inPlay
                          ? _Turn.none
                          : (iAmUp ? _Turn.mine : _Turn.theirs),
                    ),
                    Expanded(
                      child: _buildStage(
                        game: game,
                        iAmSetter: iAmSetter,
                        iAmDefender: iAmDefender,
                        mySetTurn: mySetTurn,
                        myAttempt: myAttempt,
                      ),
                    ),
                    _buildActions(
                      mySetTurn: mySetTurn,
                      myAttempt: myAttempt,
                      trickName: game.currentTrickName,
                      // Nothing this player does can reach an absent peer, so
                      // the intents are shut until the room is whole again.
                      disabled: app.peerDisconnected,
                    ),
                  ],
                ),
                if (game.phase == GamePhase.gameOver)
                  Positioned.fill(
                    child: _GameOverOverlay(
                      iWon: myId != null && game.winnerId == myId,
                      myLetters: myLetters,
                      peerLetters: peerLetters,
                      iVoted: myId != null && game.rematchVotes.contains(myId),
                      peerVoted:
                          peerId != null && game.rematchVotes.contains(peerId),
                      onRematch: widget.appState.voteRematch,
                      onLeave: widget.appState.handleLeaveMatch,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Stage — the headline that has to read at arm's length.
  // ---------------------------------------------------------------------------

  Widget _buildStage({
    required GameState game,
    required bool iAmSetter,
    required bool iAmDefender,
    required bool mySetTurn,
    required bool myAttempt,
  }) {
    final String headline;
    final String sub;
    // A "hero" trick is the one this player is about to attempt: rendered huge.
    var hero = false;
    var mine = false;

    switch (game.phase) {
      case GamePhase.setting:
        if (mySetTurn) {
          headline = 'YOUR SET';
          sub = 'Name your trick — or leave it blank.';
          mine = true;
        } else if (iAmSetter) {
          headline = 'YOUR ATTEMPT';
          sub = 'Land it to put it on them.';
          hero = true;
          mine = true;
        } else {
          headline = 'OPPONENT IS UP';
          sub = game.trickDeclared
              ? 'They are attempting their trick…'
              : 'They are choosing a trick…';
        }
      case GamePhase.defending:
        if (iAmDefender) {
          headline = 'MATCH IT';
          sub = 'Miss it and you take a letter.';
          hero = true;
          mine = true;
        } else {
          headline = 'OPPONENT IS UP';
          sub = 'They have to match your trick…';
        }
      case GamePhase.gameOver:
        headline = 'GAME OVER';
        sub = '';
      case GamePhase.abandoned:
        headline = 'OPPONENT LEFT';
        sub = '';
      case GamePhase.lobby:
        headline = 'WAITING…';
        sub = '';
    }

    // Centred when it fits, scrollable when it doesn't: the reconnect banner
    // can appear above any state, and a hero trick plus a countdown is already
    // a tall stage on a short phone.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                headline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  color: mine ? _accent : _text,
                ),
              ),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  sub,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: _muted),
                ),
              ],
              if (game.trickDeclared) ...[
                const SizedBox(height: 24),
                _TrickCard(name: game.currentTrickName, hero: hero),
              ],
              // Advisory only, and only for the player who is up (states 2 and 4).
              // The key restarts the clock on every new attempt.
              if (myAttempt) ...[
                const SizedBox(height: 20),
                AttemptTimer(
                  key: ValueKey(
                    'attempt-${game.phase.name}-${game.currentTrickName}',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions — at most one player ever has buttons here.
  // ---------------------------------------------------------------------------

  Widget _buildActions({
    required bool mySetTurn,
    required bool myAttempt,
    required String? trickName,
    required bool disabled,
  }) {
    final List<Widget> children;

    if (mySetTurn) {
      children = [
        _PresetRow(onPick: _fillTrick),
        const SizedBox(height: 12),
        TextField(
          controller: _trickController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          style: const TextStyle(
            color: _text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: _surface,
            labelText: 'TRICK NAME (OPTIONAL)',
            labelStyle: const TextStyle(
              color: _muted,
              fontSize: 12,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _accent, width: 2),
            ),
          ),
          onSubmitted: (_) => _submitTrick(),
        ),
        const SizedBox(height: 12),
        _BigButton(
          label: 'SET',
          color: _accent,
          onPressed: disabled ? null : _submitTrick,
        ),
      ];
    } else if (myAttempt) {
      children = [
        _BigButton(
          label: 'LANDED',
          color: _accent,
          onPressed: disabled ? null : () => widget.appState.reportResult(true),
        ),
        const SizedBox(height: 12),
        _BigButton(
          label: 'BAILED',
          color: _danger,
          outlined: true,
          onPressed: disabled
              ? null
              : () => widget.appState.reportResult(false),
        ),
        // Filming is local and has zero game-state effects, so it stays live
        // even while the peer is away in reconnect grace — `disabled` is
        // deliberately not consulted here.
        if (_cameraAvailable) ...[
          const SizedBox(height: 12),
          _RecordEntry(onPressed: () => _openRecorder(trickName)),
        ],
      ];
    } else {
      children = [
        Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _line),
          ),
          child: const Text(
            'WAITING FOR OPPONENT',
            style: TextStyle(
              color: _muted,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),
      ];
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// Empty trick names are legal on the wire (PROTOCOL.md §6); they read as
/// "Unnamed trick" everywhere on this screen.
String _trickLabel(String? name) =>
    (name == null || name.trim().isEmpty) ? 'Unnamed trick' : name;

class _TopBar extends StatelessWidget {
  final int? roomCode;
  final VoidCallback onLeave;

  const _TopBar({required this.roomCode, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    final code = roomCode?.toString().padLeft(5, '0') ?? '-----';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: [
          Text(
            'ROOM $code',
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: _muted),
            tooltip: 'Leave match',
            onPressed: onLeave,
          ),
        ],
      ),
    );
  }
}

enum _Turn { mine, theirs, none }

class _Scoreboard extends StatelessWidget {
  final int myLetters;
  final int peerLetters;
  final _Turn turn;

  const _Scoreboard({
    required this.myLetters,
    required this.peerLetters,
    required this.turn,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _LetterTrack(
              label: 'YOU',
              letters: myLetters,
              isUp: turn == _Turn.mine,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _LetterTrack(
              label: 'OPPONENT',
              letters: peerLetters,
              isUp: turn == _Turn.theirs,
            ),
          ),
        ],
      ),
    );
  }
}

/// S·K·A·T·E for one player. The most recently gained letter is filled red so
/// a new letter is impossible to miss; earlier ones stay quiet.
///
/// Both rows are wrapped in a scale-down [FittedBox]: the tiles keep their
/// designed size wherever there is room for them, and shrink together —
/// emphasis and all — rather than overflowing on a narrow phone. Each half of
/// the scoreboard gets the same width, so the two tracks shrink by the same
/// factor and stay in step.
class _LetterTrack extends StatelessWidget {
  final String label;
  final int letters;
  final bool isUp;

  const _LetterTrack({
    required this.label,
    required this.letters,
    required this.isUp,
  });

  static const List<String> _skate = ['S', 'K', 'A', 'T', 'E'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isUp ? _accent : _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              if (isUp) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'UP',
                    style: TextStyle(
                      color: _bg,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              for (var i = 0; i < _skate.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _LetterBox(
                  letter: _skate[i],
                  gained: i < letters,
                  latest: i == letters - 1,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LetterBox extends StatelessWidget {
  final String letter;
  final bool gained;
  final bool latest;

  const _LetterBox({
    required this.letter,
    required this.gained,
    required this.latest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: latest ? _danger : (gained ? _surface : Colors.transparent),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: latest
              ? _danger
              : (gained ? _line : _line.withValues(alpha: 0.5)),
          width: latest ? 2 : 1,
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: latest
              ? Colors.white
              : (gained ? _text : _muted.withValues(alpha: 0.35)),
          fontSize: latest ? 20 : 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TrickCard extends StatelessWidget {
  final String? name;
  final bool hero;

  const _TrickCard({required this.name, required this.hero});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hero ? _accent : _line, width: hero ? 2 : 1),
      ),
      child: Column(
        children: [
          const Text(
            'THE TRICK',
            style: TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _trickLabel(name),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _text,
                fontSize: hero ? 40 : 24,
                height: 1.1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The preset chips, state 1 only. Horizontally scrollable so the list can
/// grow without ever stealing height from the field or the SET button.
class _PresetRow extends StatelessWidget {
  final ValueChanged<String> onPick;

  const _PresetRow({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: trickPresets.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final name = trickPresets[index];
          return _TrickChip(name: name, onTap: () => onPick(name));
        },
      ),
    );
  }
}

class _TrickChip extends StatelessWidget {
  final String name;
  final VoidCallback onTap;

  const _TrickChip({required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: _line),
          ),
          child: Text(
            name,
            style: const TextStyle(
              color: _text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool outlined;

  /// Null disables the button — the reconnect-grace case.
  final VoidCallback? onPressed;

  const _BigButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w900,
      letterSpacing: 3,
      color: outlined ? color : _bg,
    );

    if (outlined) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(60),
          side: BorderSide(color: color, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
        child: Text(label, style: style),
      );
    }

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        backgroundColor: color,
        foregroundColor: _bg,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onPressed,
      child: Text(label, style: style),
    );
  }
}

/// The Record entry: a quiet third control under LANDED / BAILED, never
/// competing with them for the eye. Absent entirely where there is no camera.
class _RecordEntry extends StatelessWidget {
  final VoidCallback onPressed;

  const _RecordEntry({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        foregroundColor: _muted,
      ),
      icon: const Icon(Icons.videocam, size: 20, color: _muted),
      label: const Text(
        recordEntryLabel,
        style: TextStyle(
          color: _muted,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

/// The survivor's banner during reconnect grace. It counts down locally from
/// the `graceSeconds` the server announced; the clock is decoration, so at zero
/// it says "any moment" and waits for the server to have the last word.
class _ReconnectBanner extends StatefulWidget {
  final int seconds;

  const _ReconnectBanner({super.key, required this.seconds});

  @override
  State<_ReconnectBanner> createState() => _ReconnectBannerState();
}

class _ReconnectBannerState extends State<_ReconnectBanner> {
  Timer? _ticker;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant _ReconnectBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seconds != widget.seconds) {
      setState(_restart);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _restart() {
    _ticker?.cancel();
    _ticker = null;
    _remaining = widget.seconds < 0 ? 0 : widget.seconds;
    if (_remaining == 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _remaining--;
        if (_remaining <= 0) {
          _remaining = 0;
          _ticker?.cancel();
          _ticker = null;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _danger),
      ),
      child: Text(
        _remaining == 0
            ? reconnectingImminentLabel
            : reconnectingLabel(_remaining),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _danger,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// The rejoiner's screen between PEER_RECONNECTED and STATE_SYNC.
class _RestoringScreen extends StatelessWidget {
  const _RestoringScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  color: _accent,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                restoringLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your opponent is sending the game back.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// State 6. Covers the whole screen so the result is the only thing on it.
class _GameOverOverlay extends StatelessWidget {
  final bool iWon;
  final int myLetters;
  final int peerLetters;
  final bool iVoted;
  final bool peerVoted;
  final VoidCallback onRematch;
  final VoidCallback onLeave;

  const _GameOverOverlay({
    required this.iWon,
    required this.myLetters,
    required this.peerLetters,
    required this.iVoted,
    required this.peerVoted,
    required this.onRematch,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg.withValues(alpha: 0.97),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                iWon ? 'YOU WIN' : 'YOU LOSE',
                style: TextStyle(
                  color: iWon ? _accent : _danger,
                  fontSize: 72,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'FINAL',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 14),
            _Scoreboard(
              myLetters: myLetters,
              peerLetters: peerLetters,
              turn: _Turn.none,
            ),
            const SizedBox(height: 32),
            if (peerVoted && !iVoted) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _accent),
                ),
                child: const Text(
                  'Opponent wants a rematch',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _accent,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (iVoted)
              Container(
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _line),
                ),
                child: const Text(
                  'Waiting for opponent…',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              _BigButton(
                label: 'REMATCH',
                color: _accent,
                onPressed: onRematch,
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onLeave,
              child: const Text(
                'LEAVE MATCH',
                style: TextStyle(
                  color: _muted,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
