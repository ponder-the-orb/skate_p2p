# skate_p2p — Roadmap

**v2 — 2026-09-02.** Milestones are ordered; we do not start M(n+1) until
M(n)'s acceptance criteria pass *and* every milestone branch is certified
merged. Each ticket is sized to fit **one implementation session** — small
diffs, always shippable. Tickets live in `tickets/`, reports in `reports/`.

---

## M0 — Stabilize ✅ `v0.1.0`

One transport, no crashes, no ghost traffic. Raw TCP deleted (ADR-001),
relay echo fixed, dispatcher validates before reading, dead handshake and
auto test packet removed, first tests, `camera` removed (ADR-007, since
superseded).

## M1 — Rooms & identity ✅ `v0.2.0`

Server rooms (`JOIN`/`JOINED`/`PEER_JOINED`/`PEER_LEFT`/`ERROR`), scoped
forwarding, server-assigned `playerId` (nobody is 1024), lobby screen,
v1 control codec + dispatcher, `ClientPhase` state machine. Transitional
dual-format rules (Appendix A) carried the legacy game packets until M2.

## M2 — Protocol v1 + GameEngine ✅ `v0.4.1`

- T2.1 `GameEngine` — pure Dart reducer; the test file is the rulebook.
  Bugs caught by tests: `copyWith` null-clearing (→ `clearTrick`), and
  unnamed tricks (→ `trickDeclared`).
- T2.2 Strict v1 wire end to end; legacy v0 retired; `TRICK_SET`/
  `ATTEMPT_RESULT`/`REMATCH`; AppState hosts the engine; stale-socket guard.
- T2.3 Match screen rebuilt around the seven match states; win/lose overlay;
  rematch flow. (`v0.4.0` was tagged prematurely — see WORKFLOW §9.)

## M3 — Polish & the trick layer (closing at `v0.5.0`)

- T3.1 ✅ Preset trick chips (fill the field; SET is the only commit path)
- T3.2 ✅ Advisory attempt countdown — never acts at zero (ADR-003)
- T3.3 ✅ Reconnect grace — `PEER_DISCONNECTED 0x05` (announces
  `graceSeconds`), `PEER_RECONNECTED 0x06`, `STATE_SYNC 0x12`; the survivor
  snapshots, the rejoiner installs; zero engine lines changed
- T3.4 ⏳ Clips — record → replay → share via the system share sheet
  (ADR-008); deps `camera`, `video_player`, `share_plus`, `path_provider`
- Camera scope decision ✅ — resolved as ADR-008; in-app delivery deferred
  to ADR-005

**Acceptance:** manual passes in `docs/DEV_SETUP.md` (grace: passed on
hardware 2026-09-02; clips: pending).

## M4 — Ship

Goal: a URL and an install that a stranger can use, hardened enough to be
public, with CI so nobody merges red again.

| # | Ticket | Notes |
|---|---|---|
| T4.0 | `RELAY_URL` build-time flag | `String.fromEnvironment('RELAY_URL', defaultValue: 'ws://127.0.0.1:8080')`; documented in DEV_SETUP. Tiny; unblocks LAN and production testing |
| T4.1 | CI | GitHub Actions on push + PR: `flutter analyze`, `flutter test`, format gate, `node .../rooms_smoke.js`. Uses the built-in `GITHUB_TOKEN` only. **Acceptance includes proving it bites:** a throwaway branch with a deliberately failing test must go red |
| T4.2 | Relay hardening (before any public URL) | **Heartbeat**: ws ping/pong every 30 s, terminate on miss — bounds silent-drop detection so reconnect grace starts on a clock, not on TCP's patience. **Caps**: max connections, max rooms, JOINs per socket per minute. **Codes**: `crypto.randomInt`, 7 digits (wire already carries uint32; lobby input widens). **`ERROR 0x05` unsupported version** so stale store builds can show "update the app" (PROTOCOL edit first — Architect). Idle-room GC. Smoke tests for each |
| T4.3 | Deploy the relay | Free tier (Render / Fly.io / Railway), `wss://` via the host's TLS termination, `PORT` from env (done in T3.3), a plain `GET /healthz` for the host's uptime probe (not game state; ADR-002 unaffected). Acceptance: two phones on different networks complete a game via the public URL |
| T4.4 | App identity & friendly states | Name, icon, splash; error/empty-state copy; version shown in the lobby |
| T4.5 | README for humans | Rewrite from `docs/DEV_SETUP.md` + `docs/STRATEGY.md`; screenshots; CHANGELOG `v1.0.0-beta` section |
| T4.6 | Play internal testing track | Signing keystore **outside the repo** (WORKFLOW §7); `versionCode` scheme; tester list. TestFlight only if/when an Apple developer account exists |
| T4.7 (stretch) | Rejoin persistence | Save the last `roomCode` + `playerId` to a small JSON file in app documents (uses the already-approved `path_provider` — no new deps); lobby shows "Rejoin last game" while grace could still be live. Turns reconnect grace from a feature into a habit |

**Acceptance:** CI green on `main`; a stranger installs from the internal
track and plays a full game against the Producer over the public relay; a
mid-game kill and rejoin resumes over the public relay; `v1.0.0-beta` tagged.

## M5 — After funding (outline, not tickets)

- ADR-005: WebRTC data channels — the relay becomes a signaling server;
  game events and clip delivery go phone-to-phone; STUN free, TURN fallback
  budgeted.
- Ranked: live-witnessed attempts over WebRTC media; the attempt timer
  becomes an enforced rule in ranked only; accounts (new ADR) become
  necessary here and not before.
- Challenge mode: public, async, many-player S.K.A.T.E. seeded by shared
  clips.
- Spots / "gaps" map; matchmaking; verified-pro flair.

---

**Parking lot** (deliberate "not yet"): WebRTC true P2P (ADR-005) · accounts ·
match history · spectator mode · "last try" rule variant (engine flag exists,
UI later) · in-app clip delivery (rides ADR-005) · hardware: a tracking
tripod for solo filming · gallery export, trimming, watermarks for clips ·
horizontal relay scaling (single-process room map is fine until it isn't).

**Parking lot additions (2026-09-02, Producer + Architect session):**
· Async "challenge mode" — public many-player S.K.A.T.E. seeded by shared
  clips (Twitter/social); letters tracked per challenge
· Ranked — live-witnessed attempts over WebRTC media (recorded clips cannot
  prove one attempt; only a live window can). Attempt timer becomes the
  enforced rule in ranked only
· Spots/"gaps" map — Pokémon-Go-style discovery of real skate spots,
  lore-famous gaps as landmarks; shops; meetups
· Matchmaking + verified-pro flair (banners)
· Clip delivery in-app via WebRTC data channels (ADR-005)
· Hardware someday: tracking tripod for solo filming
