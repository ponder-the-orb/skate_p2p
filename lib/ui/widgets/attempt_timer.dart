import 'dart:async';

import 'package:flutter/material.dart';

/// How long an attempt gets, in seconds.
const int attemptSeconds = 60;

/// What the panel says once the countdown reaches zero.
const String attemptTimeUpMessage = 'TIME — land it or bail';

// The match palette, kept local to the widget exactly as it is on the match
// screen itself.
const Color _surface = Color(0xFF191D25);
const Color _line = Color(0xFF2B313C);
const Color _danger = Color(0xFFFF5C5C);
const Color _muted = Color(0xFF8B94A5);
const Color _text = Color(0xFFF3F5F9);

/// An advisory countdown, shown only to the player whose attempt it is.
///
/// It is social pressure and nothing else. At 0:00 the panel changes its
/// wording and **nothing else happens**: no auto-bail, no engine event, no
/// packet. A timeout is a *conclusion*, and conclusions never go on the wire
/// or into the engine (ADR-003); the enforced variant is parked.
///
/// The waiting player never sees it — two clocks can't be trusted to agree,
/// but one clock can't lie to its owner (ARCHITECTURE.md §5, trust model).
///
/// Self-contained: it owns its [Timer] and cancels it in [dispose]. The clock
/// restarts whenever this widget's state is (re)entered, so the match screen
/// gives it a key that changes with the attempt.
class AttemptTimer extends StatefulWidget {
  /// Seconds on the clock. Only overridden by tests.
  final int seconds;

  const AttemptTimer({super.key, this.seconds = attemptSeconds});

  @override
  State<AttemptTimer> createState() => _AttemptTimerState();
}

class _AttemptTimerState extends State<AttemptTimer> {
  Timer? _ticker;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant AttemptTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seconds != widget.seconds) {
      setState(_restart);
    }
  }

  @override
  void dispose() {
    // A leaked timer fails widget tests on its own. Let that guard us.
    _ticker?.cancel();
    super.dispose();
  }

  void _restart() {
    _ticker?.cancel();
    _ticker = null;
    _remaining = widget.seconds < 0 ? 0 : widget.seconds;
    if (_remaining == 0) {
      return;
    }
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

  static String _clock(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  @override
  Widget build(BuildContext context) {
    final expired = _remaining == 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: expired ? _danger : _line,
          width: expired ? 2 : 1,
        ),
      ),
      child: expired
          ? const Text(
              attemptTimeUpMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _danger,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ATTEMPT TIME',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  _clock(_remaining),
                  style: const TextStyle(
                    color: _text,
                    fontSize: 22,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
    );
  }
}
