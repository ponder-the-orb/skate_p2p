REPORT M3-T3.3 — DONE
CHANGED: server.js (+150 −53) · rooms_smoke.js (+161 −15) · packet_codec.dart (+215) ·
  packet_dispatcher.dart (+17) · app_state.dart (+120) · match_screen.dart (+222 −44) ·
  4 test files (+818). lib/game/ diff: 0 lines.
CHECKS: analyze ✅  test ✅ (132 passed)  format ✅  rooms_smoke.js ✅ (GRACE_MS=200)
COMMITS: feat(server): hold a dropped peer's seat for a reconnect grace window ·
  feat(net): STATE_SYNC and the reconnect-grace control opcodes ·
  feat(ui): reconnect banner, disabled intents and the restoring state · docs: changelog
CHANGELOG: updated
QUESTIONS/FLAGS: see below
DIFF: https://github.com/ponder-the-orb/skate_p2p/compare/main...m3/reconnect-grace
PR: https://github.com/ponder-the-orb/skate_p2p/pull/new/m3/reconnect-grace (needs gh auth login here)
FLAGS — four judgement calls worth a look:
1. PORT is now env-overridable in server.js (alongside the specified GRACE_MS). rooms_smoke.js starts its own relay on port 8129 with GRACE_MS=200, so node skate_signaling_server/test/rooms_smoke.js is now self-contained and no longer needs a hand-started server — and it won't collide with a dev relay on 8080.
2. The rejoiner goes inMatch on 0x06, not on the snapshot. Otherwise a role-1 rejoiner sits on the lobby screen and the required "Restoring game…" state is unreachable. It is still inMatch after the install, as the ticket says.
3. The stage is now scrollable. Adding the banner overflowed the match screen by 27 px on a short viewport (banner + hero trick + attempt timer) — a real render error, caught by the widget test. Same SingleChildScrollView idiom the game-over overlay already used.
4. REMATCH stays enabled during grace. Only SET / LANDED / BAILED are disabled. A vote cast while the peer is away is carried in the flags byte of the eventual 0x12, so it survives the rejoin correctly; the game-over overlay also covers the banner in that state. Say the word if you'd rather it were disabled too.
Manual acceptance (kill mid-game → countdown → relaunch and rejoin → identical state; and a separate expiry run) is yours to run — it's the one line of the acceptance list I can't execute here.
