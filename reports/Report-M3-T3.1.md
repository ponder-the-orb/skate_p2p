REPORT M3-T3.1 — DONE
CHANGED: lib/ui/data/trick_presets.dart (new, +34) · lib/ui/screens/match_screen.dart (+73 −1) · test/trick_presets_test.dart (new, +35) · test/match_screen_test.dart (+56) · CHANGELOG.md (+6)
CHECKS: analyze ✅  test ✅ (85 passed)  format ✅ (--set-exit-if-changed clean)
COMMITS: feat(ui): preset trick chips on the setter panel
CHANGELOG: updated under [Unreleased]
QUESTIONS/FLAGS: (1) gh is not authenticated in this environment, so I pushed the branch but could not open the PR — the link below opens it pre-filled. (2) Base is m2/polish, not main: this ticket edits the state-1 setter panel that T2.3 built, and m2/polish is still unmerged (5 commits ahead of main). If T2.3's PR lands first, retarget this one to main.
DIFF: https://github.com/ponder-the-orb/skate_p2p/compare/m2/polish...m3/trick-presets?expand=1
What landed:
- lib/ui/data/trick_presets.dart — one const List<String> trickPresets, 23 PG street tricks from Ollie to Nollie Tre Flip, roughly easy → hard. No logic, no imports.
- State 1 only — a SizedBox(height: 38) wrapping a horizontal ListView.separated of chips, above the trick field. _fillTrick sets the controller's value with the caret at the end, so the name is immediately editable; SET remains the only thing that calls appState.setTrick. The row is inside the existing mySetTurn branch of _buildActions, so it cannot leak into states 2–6.
- trick_presets_test.dart — non-empty, no blank entries, no duplicates, and every name ≤ 254 bytes once utf8.encoded, which is the nameLen uint8 ceiling from PROTOCOL.md §6.
- match_screen_test.dart — state 1 gains four tests (chips render, tap fills the field without declaring, SET after a tap declares that exact name via app.game.currentTrickName, a filled preset is still editable). State 2's "nothing else" assertion picked up one line confirming the chips are gone; every other existing test is untouched and still passes.
✻ Brewed for 2m 46s · done 7:42 PM
