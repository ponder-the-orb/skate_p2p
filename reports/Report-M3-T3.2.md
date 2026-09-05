REPORT M3-T3.2 — DONE
CHANGED: lib/ui/widgets/attempt_timer.dart (new, +142) · lib/ui/screens/match_screen.dart (+13) · test/attempt_timer_test.dart (new, +99) · test/match_screen_test.dart (+85) · CHANGELOG.md (+8)
CHECKS: analyze ✅  test ✅ (86 passed)  format ✅  engine/net/state/server/protocol diff: 0 lines
COMMITS: feat(ui): advisory attempt countdown in states 2 and 4 · test(ui): cover the attempt countdown · docs: changelog entry for M3-T3.2
CHANGELOG: updated
QUESTIONS/FLAGS: gh CLI not authenticated here — PR not opened from the terminal; open it from the link below. Timer restarts are keyed on 'attempt-${phase}-${trickName}'; as the engine stands today every attempt is separated by a state with no timer, so the key is belt-and-braces rather than load-bearing.
DIFF: https://github.com/ponder-the-orb/skate_p2p/pull/new/m3/attempt-timer  (compare: https://github.com/ponder-the-orb/skate_p2p/compare/main...m3/attempt-timer)
Two things worth knowing beyond the template:
- The dispose guard is verified, not assumed. I temporarily deleted _ticker?.cancel() from dispose() and re-ran attempt_timer_test — it failed with "A Timer is still pending even after the widget tree was disposed" on four tests, then I restored it. The guard the ticket asked for is real and biting.
- Nothing acts at zero. match_screen_test asserts it explicitly: after 60 seconds of pumped time, phase, letters, trickDeclared and both buttons are exactly what they were — only the panel's wording changed.
✻ Crunched for 5m 30s · done 9:33 PM
