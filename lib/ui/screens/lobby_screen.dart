import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/state/app_state.dart';
import '../../core/network/signaling_service.dart';
import '../../core/network/packet_codec.dart';
import 'clip_replay_screen.dart';

/// The lobby's way into the local clip library.
const String myClipsLabel = 'MY CLIPS';

class LobbyScreen extends StatefulWidget {
  final AppState appState;
  final SignalingService signalingService;

  const LobbyScreen({
    super.key,
    required this.appState,
    required this.signalingService,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isJoinEnabled = false;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
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
