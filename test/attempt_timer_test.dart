import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skate_p2p/ui/widgets/attempt_timer.dart';

/// Wraps the timer in the least screen we can get away with.
Future<void> _pumpTimer(WidgetTester tester, {int? seconds}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: seconds == null
            ? const AttemptTimer()
            : AttemptTimer(seconds: seconds),
      ),
    ),
  );
}

void main() {
  group('AttemptTimer', () {
    testWidgets('starts on the full minute', (tester) async {
      await _pumpTimer(tester);

      expect(attemptSeconds, 60);
      expect(find.text('1:00'), findsOneWidget);
      expect(find.text(attemptTimeUpMessage), findsNothing);

      // Leave nothing pending behind us.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('counts down a second at a time', (tester) async {
      await _pumpTimer(tester);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0:59'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0:58'), findsOneWidget);

      await tester.pump(const Duration(seconds: 8));
      expect(find.text('0:50'), findsOneWidget);
      expect(find.text('1:00'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('flips to the time-is-up treatment at zero', (tester) async {
      await _pumpTimer(tester, seconds: 3);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('0:01'), findsOneWidget);
      expect(find.text(attemptTimeUpMessage), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text(attemptTimeUpMessage), findsOneWidget);
      expect(find.text('0:00'), findsNothing);
    });

    testWidgets('stops at zero — it never goes negative and never acts', (
      tester,
    ) async {
      await _pumpTimer(tester, seconds: 2);

      await tester.pump(const Duration(seconds: 30));

      // Still just a message. Nothing else on screen changed, because the
      // timer is advisory: no auto-bail, no event, no packet (ADR-003).
      expect(find.text(attemptTimeUpMessage), findsOneWidget);
    });

    testWidgets('cancels its timer when it leaves the tree', (tester) async {
      await _pumpTimer(tester);

      await tester.pump(const Duration(seconds: 5));
      expect(find.text('0:55'), findsOneWidget);

      // If dispose() forgot to cancel, the pending timer fails this test.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(find.byType(AttemptTimer), findsNothing);
    });

    testWidgets('a fresh widget state starts the clock over', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AttemptTimer(key: ValueKey('attempt-1'))),
        ),
      );

      await tester.pump(const Duration(seconds: 20));
      expect(find.text('0:40'), findsOneWidget);

      // A different key is a different attempt: new State, full clock.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AttemptTimer(key: ValueKey('attempt-2'))),
        ),
      );
      expect(find.text('1:00'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
