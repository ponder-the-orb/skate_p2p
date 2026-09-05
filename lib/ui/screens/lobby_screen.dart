import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/state/app_state.dart';
import '../../core/network/signaling_service.dart';
import '../../core/network/packet_codec.dart';
import '../../media/rejoin_store.dart';
import 'clip_replay_screen.dart';

/// The lobby's way into the local clip library.
const String myClipsLabel = 'MY CLIPS';

/// The lobby's way back into the game the app was killed out of.
const String rejoinLabel = 'REJOIN LAST GAME';

/// How stale a save may be and still be worth offering. Grace is 120 s
/// (PROTOCOL.md §5, announced on the wire and never hardcoded as *the rule*);
/// the extra 60 covers the relaunch itself.
///
/// A display heuristic and nothing more. The client never concludes a room is
/// dead — only the server knows that, and it says so with `0x0F 0x02`.
const Duration rejoinFreshness = Duration(seconds: 180);

class LobbyScreen extends StatefulWidget {
  final AppState appState;
  final SignalingService signalingService;

  /// Overrides the store `main.dart` attached to [appState]. Tests pass a
  /// temp-directory store here; the app never sets it.
  final RejoinStore? rejoinStore;

  const LobbyScreen({
    super.key,
    required this.appState,
    required this.signalingService,
    this.rejoinStore,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isJoinEnabled = false;

  /// The last game, if it is recent enough to offer. Read once — a lobby that
  /// re-read the disk on every rebuild would be doing IO inside build().
  RejoinRecord? _rejoin;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
    _loadRejoin();
  }

  Future<void> _loadRejoin() async {
    final store = widget.rejoinStore ?? widget.appState.rejoinStore;
    if (store == null) return; // Feature off: no store, no button, no error.

    final record = await store.load();
    if (!mounted) return;
    if (record == null || record.age() > rejoinFreshness) return;

    setState(() => _rejoin = record);
  }

  /// A plain JOIN with the saved code — nothing else goes on the wire. The
  /// server re-seats the original playerId itself (PROTOCOL.md §5), so the
  /// saved id is never sent; it is remembered for the logs.
  void _onRejoinPressed(RejoinRecord record) {
    widget.appState.clearNotice();
    widget.appState.markRejoinAttempt(record.roomCode);
    widget.signalingService.sendBinary(
      PacketCodec.encodeJoin(roomCode: record.roomCode, senderId: 0x0000),
    );
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    setState(() {
      _isJoinEnabled = _codeController.text.length == 5;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, child) {
        final phase = widget.appState.phase;
        final isConnected = widget.appState.isConnected;

        return Scaffold(
          appBar: AppBar(
            title: const Text('SKATE P2P LOBBY'),
            centerTitle: true,
            backgroundColor: Colors.black87,
            foregroundColor: Colors.white,
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Network Connection status at top
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isConnected
                            ? Colors.greenAccent
                            : Colors.redAccent,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConnected
                                ? Colors.greenAccent
                                : Colors.redAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isConnected ? 'CONNECTED' : 'DISCONNECTED',
                          style: TextStyle(
                            color: isConnected
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Main content depends on ClientPhase
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (phase == ClientPhase.disconnected) ...[
                            const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Connecting to server...',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ] else if (phase == ClientPhase.waitingForPeer) ...[
                            _buildWaitingForPeerSection(),
                          ] else ...[
                            _buildLobbyIdleSection(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLobbyIdleSection() {
    final notice = widget.appState.notice;
    final errorNotice = widget.appState.errorNotice;
    final rejoin = _rejoin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Short Notice if any (e.g. peer left)
        if (notice != null) ...[
          _Notice(
            label: 'HEADS UP',
            message: notice,
            color: Colors.blueGrey,
            textColor: Colors.white,
          ),
          const SizedBox(height: 20),
        ],

        // Error Notice if any (inline, no SnackBars)
        if (errorNotice != null) ...[
          _Notice(
            label: 'ERROR',
            message: errorNotice,
            color: Colors.redAccent,
            textColor: Colors.redAccent,
          ),
          const SizedBox(height: 20),
        ],

        // The way back into a game this app was killed out of. Above CREATE
        // ROOM because that is the whole point: the player who relaunches
        // mid-game wants one tap, not a remembered code.
        if (rejoin != null) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => _onRejoinPressed(rejoin),
            icon: const Icon(Icons.replay, size: 20),
            label: Text(
              '$rejoinLabel  ·  ${rejoin.roomCode.toString().padLeft(5, '0')}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Create Room Section
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () {
            widget.appState.clearNotice();
            final packet = PacketCodec.encodeJoin(
              roomCode: 0,
              senderId: 0x0000,
            );
            widget.signalingService.sendBinary(packet);
          },
          child: const Text(
            'CREATE ROOM',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),

        const SizedBox(height: 40),

        Row(
          children: const [
            Expanded(child: Divider(color: Colors.grey)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('OR', style: TextStyle(color: Colors.grey)),
            ),
            Expanded(child: Divider(color: Colors.grey)),
          ],
        ),

        const SizedBox(height: 40),

        // Join Room Section
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'JOIN EXISTING ROOM',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(5),
                  ],
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '5-Digit Room Code',
                    hintText: 'e.g. 41235',
                    counterText: '',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isJoinEnabled
                      ? () {
                          widget.appState.clearNotice();
                          final roomCode =
                              int.tryParse(_codeController.text) ?? 0;
                          final packet = PacketCodec.encodeJoin(
                            roomCode: roomCode,
                            senderId: 0x0000,
                          );
                          widget.signalingService.sendBinary(packet);
                        }
                      : null,
                  child: const Text(
                    'JOIN',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Clips are local and have nothing to do with a match (ADR-008), so
        // the way in is a quiet side door on the idle lobby.
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => const MyClipsScreen(),
            ),
          ),
          icon: const Icon(Icons.video_library, size: 18, color: Colors.grey),
          label: const Text(
            myClipsLabel,
            style: TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingForPeerSection() {
    final roomCode = widget.appState.roomCode;
    final displayCode = roomCode?.toString().padLeft(5, '0') ?? '-----';

    return Column(
      children: [
        const Text(
          'ROOM CREATED',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          displayCode,
          style: const TextStyle(
            fontSize: 54,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            color: Colors.greenAccent,
          ),
        ),
        const SizedBox(height: 24),
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.greenAccent,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'waiting for peer…',
          style: TextStyle(
            fontSize: 16,
            fontStyle: FontStyle.italic,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 48),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.redAccent),
            foregroundColor: Colors.redAccent,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () {
            widget.appState.handleCancel();
          },
          child: const Text(
            'CANCEL',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

/// A lobby notice — "peer left", "room full". Same bordered-panel language as
/// the match screen so the two screens read as one app.
class _Notice extends StatelessWidget {
  final String label;
  final String message;
  final Color color;
  final Color textColor;

  const _Notice({
    required this.label,
    required this.message,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
