import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../media/clip_store.dart';
import '../clip_environment.dart';

// The match palette, kept local to the screen as everywhere else in `ui/`.
const Color _bg = Color(0xFF0E1014);
const Color _surface = Color(0xFF191D25);
const Color _line = Color(0xFF2B313C);
const Color _accent = Color(0xFFD8FF3E);
const Color _danger = Color(0xFFFF5C5C);
const Color _muted = Color(0xFF8B94A5);
const Color _text = Color(0xFFF3F5F9);

/// Shown in place of the preview when the file will not play. Share and Delete
/// still work: a clip that this device cannot decode is still a file worth
/// sending or throwing away.
const String clipUnplayableMessage = 'Can’t play this clip here';

/// Watch a clip back, then Share, Delete, or keep it.
///
/// Back keeps the file — kept clips show up in [MyClipsScreen]. Sharing goes
/// through the OS share sheet with the challenge line from
/// [ClipStore.shareText]; there is no in-app delivery and no upload (ADR-008).
class ClipReplayScreen extends StatefulWidget {
  final ClipStore store;
  final Clip clip;

  /// The trick that was being attempted, if this replay came straight off a
  /// recording. Null from the "My clips" list, where it reads as "this".
  final String? trickName;

  const ClipReplayScreen({
    super.key,
    required this.store,
    required this.clip,
    this.trickName,
  });

  @override
  State<ClipReplayScreen> createState() => _ClipReplayScreenState();
}

class _ClipReplayScreenState extends State<ClipReplayScreen> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  Future<void> _open() async {
    final controller = VideoPlayerController.file(widget.clip.file);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: ClipStore.shareText(widget.trickName),
          files: [XFile(widget.clip.path)],
        ),
      );
    } catch (_) {
      // A share sheet that will not open is not worth an error screen; the
      // clip is still on the phone.
    }
  }

  Future<void> _delete() async {
    await widget.store.delete(widget.clip);
    if (!mounted) return;
    // `true` tells the list it should reload.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              title: 'YOUR CLIP',
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(child: Center(child: _buildPreview())),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BigButton(label: 'SHARE', color: _accent, onPressed: _share),
                  const SizedBox(height: 12),
                  _BigButton(
                    label: 'DELETE',
                    color: _danger,
                    outlined: true,
                    onPressed: _delete,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'BACK — KEEP IT',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_failed) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_disabled, color: _muted, size: 44),
            SizedBox(height: 16),
            Text(
              clipUnplayableMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _text,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'You can still share it or delete it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(color: _accent, strokeWidth: 3),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

/// Every clip kept on this phone, newest first.
///
/// Reached from the lobby. It is a plain local list — no accounts, no sync, no
/// upload; the files never leave the device except through a share sheet.
class MyClipsScreen extends StatefulWidget {
  /// Injectable so a test can point the screen at a temp directory. The app
  /// leaves it null and the screen resolves the real store itself.
  final ClipStore? store;

  const MyClipsScreen({super.key, this.store});

  @override
  State<MyClipsScreen> createState() => _MyClipsScreenState();
}

class _MyClipsScreenState extends State<MyClipsScreen> {
  ClipStore? _store;
  List<Clip>? _clips;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final store = widget.store ?? _store ?? await resolveClipStore();
      final clips = await store.list();
      if (!mounted) return;
      setState(() {
        _store = store;
        _clips = clips;
      });
    } catch (_) {
      if (!mounted) return;
      // No documents directory is the same thing as no clips.
      setState(() => _clips = const <Clip>[]);
    }
  }

  Future<void> _openClip(Clip clip) async {
    final store = _store;
    if (store == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => ClipReplayScreen(store: store, clip: clip),
      ),
    );
    // Reload unconditionally: the clip may have been deleted, and a list that
    // lies about what is on disk is worse than one extra directory read.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final clips = _clips;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              title: 'MY CLIPS',
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: clips == null
                  ? const Center(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          color: _accent,
                          strokeWidth: 3,
                        ),
                      ),
                    )
                  : clips.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'No clips yet. Film an attempt during a game.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted, fontSize: 15),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: clips.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final clip = clips[index];
                        return _ClipRow(
                          label: formatClipDate(clip.recordedAt),
                          onTap: () => _openClip(clip),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The clip's own timestamp, read back off its filename — the only label a
/// clip has, because nothing else about it is persisted.
String formatClipDate(DateTime at) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = at.hour.toString().padLeft(2, '0');
  final minute = at.minute.toString().padLeft(2, '0');
  return '${at.day} ${months[at.month - 1]} ${at.year} · $hour:$minute';
}

class _ClipRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ClipRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: Row(
            children: [
              const Icon(Icons.play_circle_fill, color: _accent, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const _TopBar({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
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
            tooltip: 'Back',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

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
