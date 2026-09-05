REPORT M2-T2.3 — DONE
CHANGED: lib/ui/screens/match_screen.dart (+660 −153) · lib/ui/screens/lobby_screen.dart (+55 −35) · test/match_screen_test.dart (+217 new) · test/widget_test.dart (+2 −2, format only) · CHANGELOG.md (+9)
CHECKS: analyze ✅  test ✅ (77 passed)  format ✅ (--set-exit-if-changed clean repo-wide)
COMMITS: style: dart format fallout in test/widget_test.dart · feat(ui): rebuild match screen around the seven match states · feat(ui): give lobby notices the match screen's panel styling · test(ui): widget tests for match states 1-6 · docs: changelog entry for M2-T2.3
CHANGELOG: updated
QUESTIONS/FLAGS: PR not opened — gh is unauthenticated on this machine; branch pushed, needs a human click. GEMINI.md has an uncommitted edit that was already in the working tree (Current focus → M3); left untouched, not committed.
DIFF: https://github.com/ponder-the-orb/skate_p2p/compare/main...m2/polish
What's in it:
- States 1–6 each get their own layout, driven only by game.phase, setterId/defenderId, trickDeclared and my playerId/peerId. Nothing needed a rule the engine doesn't already expose, so no FLAG there.
- Letters are an accumulating S·K·A·T·E track per player; the most recently gained letter is filled red and slightly larger — derived from the count alone, so no animation deps and no engine change.
- Game over is a full-screen overlay over the board: WIN/LOSE huge, FINAL letters for both, REMATCH → "Waiting for opponent…" once I've voted, with "Opponent wants a rematch" when the peer votes first. It disappears on its own when both votes land and the engine resets.
- Lobby touch was notice-only: the two inline containers became one _Notice widget with a label and the match screen's panel styling.
- Tests (10, one per state plus the win/lose/vote variants of state 6) reach each state by playing the real game through setTrick/reportResult/voteRematch and applyRemoteEvent — e.g. five land-then-peer-bail rounds to reach gameOver as the winner.
gh isn't authenticated here, so the PR isn't opened — the branch is pushed and ready. You can open it with ! gh auth login then re-run, or click through the compare link below.
