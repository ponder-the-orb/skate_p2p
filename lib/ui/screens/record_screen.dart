import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../clip_environment.dart';
import 'clip_replay_screen.dart';

// The match palette, kept local to the screen exactly as it is everywhere else
// in `ui/`.
const Color _bg = Color(0xFF0E1014);
const Color _surface = Color(0xFF191D25);
const Color _accent = Color(0xFFD8FF3E);
const Color _danger = Color(0xFFFF5C5C);
const Color _muted = Color(0xFF8B94A5);
const Color _text = Color(0xFFF3F5F9);

/// The hard cap on a clip, in seconds. Short on purpose: share sheets and
/// messengers are the destination, and a 30-second file arrives everywhere.
const int clipMaxSeconds = 30;

/// What the screen says when the camera cannot be had. It is a state, never an
/// exception thrown at the player.
const String cameraUnavailableMessage = 'Camera unavailable';

/// Film your own attempt.
///
/// Recording is **manual start only** — no auto-record, ever (privacy,
/// ADR-008) — and has **zero** game-state effects: nothing here reports a
/// result, touches `AppState.game`, or puts a byte on the wire. It stays usable
/// while the peer is away in reconnect grace, because it is entirely local.
///
/// This is a `Navigator` route rather than a phase of the match root: record
/// and replay are user-driven, synchronous flows. The phase-driven root stays
/// authoritative for everything the network decides (the T1.2 ruling), so if a
/// network transition fires mid-recording, the root simply wins the moment the
/// player backs out of here.
class RecordScreen extends StatefulWidget {
  /// The trick being attempted, used only to build the share line.
  final String? trickName;

  const RecordScreen({super.key, this.trickName});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

enum _Stage { initializing, ready, recording, saving, unavailable }

class _RecordScreenState extends State<RecordScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  _Stage _stage = _Stage.initializing;
  Timer? _ticker;
  int _remaining = clipMaxSeconds;

  /// Guards the two paths into [_stop] — the button and the cap expiring —
  /// against firing at once.
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Not awaited: dispose() cannot be async, and an orphaned controller that
    // is closing is still better than one that is held open.
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  /// The lifecycle dance that camera features die on: hand the hardware back
  /// when we go inactive, take it again on resume.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive) {
      _releaseCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && mounted) {
        setState(() => _stage = _Stage.initializing);
        _initCamera();
      }
    }
  }

  void _releaseCamera() {
    _ticker?.cancel();
    _ticker = null;
    final controller = _controller;
    _controller = null;
    // An in-flight recording does not survive backgrounding, and pretending
    // otherwise is how you end up with a half-written file.
    controller?.dispose();
    if (mounted) {
      setState(() {
        _stage = _Stage.initializing;
        _stopping = false;
        _remaining = clipMaxSeconds;
      });
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _fail();
        return;
      }
      final description = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _stage = _Stage.ready;
      });
    } catch (_) {
      // No plugin (Linux desktop), no permission, no hardware — one answer.
      _fail();
    }
  }

  void _fail() {
    if (!mounted) return;
    setState(() {
      _controller = null;
      _stage = _Stage.unavailable;
    });
  }

  Future<void> _start() async {
    final controller = _controller;
    if (controller == null || _stage != _Stage.ready) return;

    try {
      await controller.startVideoRecording();
    } catch (_) {
      _fail();
      return;
    }
    if (!mounted) return;

    setState(() {
      _stage = _Stage.recording;
      _remaining = clipMaxSeconds;
      _stopping = false;
    });

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = _remaining - 1;
      setState(() => _remaining = next < 0 ? 0 : next);
      // The cap stops the take by itself; the player is not asked to.
      if (next <= 0) _stop();
    });
  }

  Future<void> _stop() async {
    final controller = _controller;
    if (controller == null || _stopping) return;
    _stopping = true;

    _ticker?.cancel();
    _ticker = null;
    setState(() => _stage = _Stage.saving);

    try {
      final file = await controller.stopVideoRecording();
      final store = await resolveClipStore();
      final clip = await store.adopt(file.path);
      if (!mounted) return;
      // Replaces this route, so Back from the replay lands on the match again
      // rather than on a live viewfinder.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => ClipReplayScreen(
            store: store,
            clip: clip,
            trickName: widget.trickName,
          ),
        ),
      );
    } catch (_) {
      _fail();
    } finally {
      _stopping = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              // Backing out mid-recording throws the take away rather than
              // silently keeping it — the player never started a save.
              onClose: () => Navigator.of(context).maybePop(),
              trickName: widget.trickName,
            ),
            Expanded(child: Center(child: _buildViewfinder())),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildViewfinder() {
    final controller = _controller;

    switch (_stage) {
      case _Stage.unavailable:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off, color: _muted, size: 44),
              SizedBox(height: 16),
              Text(
                cameraUnavailableMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _text,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Filming is off for now. The game is unaffected.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 14),
              ),
            ],
          ),
        );
      case _Stage.initializing:
      case _Stage.saving:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(color: _accent, strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              _stage == _Stage.saving ? 'Saving clip…' : 'Waking the camera…',
              style: const TextStyle(color: _muted, fontSize: 14),
            ),
          ],
        );
      case _Stage.ready:
      case _Stage.recording:
        if (controller == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 1 / controller.value.aspectRatio,
              child: CameraPreview(controller),
            ),
          ),
        );
    }
  }

  Widget _buildControls() {
    final recording = _stage == _Stage.recording;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (recording) ...[
            _RemainingBar(remaining: _remaining),
            const SizedBox(height: 12),
          ],
          if (_stage == _Stage.unavailable)
            _BigButton(
              label: 'BACK',
              color: _accent,
              outlined: true,
              onPressed: () => Navigator.of(context).maybePop(),
            )
          else
            _BigButton(
              label: recording ? 'STOP' : 'RECORD',
              color: recording ? _danger : _accent,
              outlined: recording,
              // Manual start only — nothing on this screen ever begins a
              // recording on the player's behalf.
              onPressed: _stage == _Stage.ready
                  ? _start
                  : (recording ? _stop : null),
            ),
        ],
      ),
    );
  }
}

/// The remaining-seconds indicator. Visible for the whole take, so the 30-second
/// auto-stop is never a surprise.
class _RemainingBar extends StatelessWidget {
  final int remaining;

  const _RemainingBar({required this.remaining});

  @override
  Widget build(BuildContext context) {
    final left = remaining < 0 ? 0 : remaining;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _danger, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: _danger,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'REC',
                style: TextStyle(
                  color: _danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          Text(
            '${left}s left',
            style: const TextStyle(
              color: _text,
              fontSize: 20,
              height: 1.0,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onClose;
  final String? trickName;

  const _TopBar({required this.onClose, required this.trickName});

  @override
  Widget build(BuildContext context) {
    final trick = trickName?.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              (trick == null || trick.isEmpty)
                  ? 'FILM YOUR ATTEMPT'
                  : 'FILMING · ${trick.toUpperCase()}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: _muted),
            tooltip: 'Back to the match',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// The clips screens' button, same shape as the match screen's.
class _BigButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool outlined;
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
