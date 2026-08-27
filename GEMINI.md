# skate_p2p — Programmer's standing orders

Two-player S.K.A.T.E. game: Flutter client + Node WebSocket binary relay. You implement tickets written by the Architect. This file is loaded every session — it stays short on purpose. Depth lives in `docs/`.

## Read before coding
- `docs/ARCHITECTURE.md` — layers, game rules, decision log (ADRs)
- `docs/PROTOCOL.md` — the wire format. **Single source of truth.** If code disagrees with it, the code is wrong.
- `docs/ROADMAP.md` — current milestone; do not work ahead of it
- `docs/WORKFLOW.md` — ticket/report formats, git rules

## Golden rules
1. All networking is **binary over WebSocket**. No JSON on the wire, no HTTP/REST endpoints for game state.
2. **Never change the wire format** (opcodes, header, payload layouts) on your own. If a ticket seems to need it: stop, report `BLOCKED: needs Architect`.
3. `lib/game/` is **pure Dart** — no Flutter imports, no socket imports, ever. All game rules live there and nowhere else.
4. All multi-byte integers are **big-endian** (`ByteData` default / Node `BE` functions).
5. Validate every incoming packet per `PROTOCOL.md §3` before reading any field. Malformed input is dropped and logged, never thrown on.
6. **No new dependencies** without Producer approval — propose in your report instead.
7. Work the ticket, only the ticket. Refactors you notice along the way go in the report's FLAGS line, not in the diff.
8. Small diffs. If a ticket is ballooning, stop and report rather than pushing a monster.

## Definition of done (every ticket)
- [ ] `flutter analyze` clean · `flutter test` passes · `dart format` applied
- [ ] Tests added/updated for the changed behavior
- [ ] Conventional commit(s): `feat(net): …` / `fix(server): …` / `test(game): …`
- [ ] `CHANGELOG.md` entry under `[Unreleased]`
- [ ] Five-line report per `WORKFLOW.md §4`, with the GitHub diff link

## Never
Force-push · rewrite `main` history · commit secrets or tokens · print the GitHub token · edit `docs/ARCHITECTURE.md` or `docs/PROTOCOL.md` (Architect-owned — propose changes in reports)

## Current focus
**M1 — Rooms & identity** (see `docs/ROADMAP.md`). The Architect updates this line as milestones close.
