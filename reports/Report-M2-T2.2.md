REPORT M2-T2.2 — DONE
  CHANGED: server.js, rooms_smoke.js, packet_codec.dart, packet_dispatcher.dart,
           app_state.dart, match_screen.dart, main.dart, +app_state_test.dart,
           −binary_packer.dart, −binary_packer_test.dart, CHANGELOG.md (+1069 −477)
  CHECKS: analyze ✅  test ✅ (67 passed)  rooms_smoke ✅  dart format ✅
  COMMITS: feat(server): enforce strict protocol v1 framing and routing
           feat(net): run the game on protocol v1 and retire legacy v0
           docs: changelog entry for M2-T2.2
  CHANGELOG: updated
  QUESTIONS/FLAGS: gh CLI not installed — branch pushed, PR not opened.
           lib/game/game_engine.dart is not dart format-clean on main; I
           reverted the reformat to keep it out of this diff (engine untouched).
  DIFF: https://github.com/ponder-the-orb/skate_p2p/compare/main...m2/protocol-v1
  PR:   https://github.com/ponder-the-orb/skate_p2p/pull/new/m2/protocol-v1
  Notes on the two judgment calls inside the ticket:
  - Rejected local intents still commit the engine snapshot (so lastRejectedReason is observable to the UI) but send nothing — "do nothing further" read as "nothing goes on the wire".
  - Remote events are keyed to the stored peerId, not the frame's senderId. In a two-socket room they're always equal, and trusting the local value can't be spoofed by a buggy peer.
  docs/PROTOCOL.md and docs/WORKFLOW.md had uncommitted Architect edits in the tree when I started (the updated §5 among them) — left untouched and uncommitted, as they're Architect-owned.
