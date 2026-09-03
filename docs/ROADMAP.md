# skate_p2p — Roadmap

Milestones are ordered; we do not start M(n+1) until M(n)'s acceptance criteria pass. Each ticket is sized to fit **one implementation session** — small diffs, always shippable.

---

## M0 — Stabilize (no new features)

Goal: one transport, no crashes, no ghost traffic. This is pure debt payoff.

| # | Task | Notes |
|---|---|---|
| T0.1 | Delete `lib/core/network/network_service.dart` and the HOST/CONNECT UI in `main.dart`; route the app to the WebSocket path only | ADR-001. The code survives in git history — delete, don't comment out |
| T0.2 | `server.js`: stop echoing to the sender (`client !== ws` guard in the broadcast loop) | Fixes the score-corruption and both-players-think-it's-their-turn bugs |
| T0.3 | `PacketDispatcher`: validate before reading — length ≥ header, length matches expected size per opcode; drop + log bad packets, never throw | PROTOCOL.md §3 discipline, applied to the v0 format for now |
| T0.4 | Remove the auto test packet on connect and the dead handshake pack/parse code | Debug traffic that ships becomes protocol |
| T0.5 | Tests: `BinaryPacker` round-trips (pack → parse → same values) + dispatcher rejects truncated/garbage input without throwing | First `test/` directory in the project |
| T0.6 | Remove `camera` from `pubspec.yaml` | ADR-007; re-add at M3 |

**Acceptance:** two emulators/devices play through the relay with no cross-talk and no echo; feeding the dispatcher garbage bytes logs and continues; `flutter analyze` is clean; `flutter test` passes; CHANGELOG.md exists with entries for the above.

## M1 — Rooms & identity

Goal: two concurrent games can't see each other; nobody is player `1024`.

- Server: room map, `JOIN`/`JOINED`/`PEER_JOINED`/`PEER_LEFT`/`ERROR` per PROTOCOL.md §5, forward game opcodes only within the room, room cleanup when both sockets close.
- Client: lobby screen — **Create** (shows the 5-digit code) / **Join** (enter code); store server-assigned `playerId`; handle `PEER_LEFT` → back to lobby with a message.
- Tests: a small Node test (or scripted `wscat` run) proving a third client gets `room full` and that packets never cross rooms.

**Acceptance:** two separate pairs of clients play simultaneously with zero leakage; joining a bad code shows a friendly error.

## M2 — Protocol v1 + GameEngine (the big one)

Goal: the real game, deterministically synced.

- Implement PROTOCOL.md v1: version byte, new header, new codec (`PacketCodec` replaces `BinaryPacker` + parse side of dispatcher).
- `lib/game/game_engine.dart` — pure Dart reducer implementing the full rules table in ARCHITECTURE.md §5. **The test file for this is the rulebook**: every row of the table is a test case, plus letters accumulating to game over, rematch requiring both votes, and abandonment.
- Replace the turn/score packets and buttons with: *Set trick* (name entry or "unnamed") → *I landed it / I bailed* → derived phases drive the UI. Delete `isMyTurn` from AppState.
- Single match screen replaces the current two half-screens; win/lose overlay + rematch button.

**Acceptance:** a full best-effort game of S.K.A.T.E. start-to-finish on two devices, including a rematch; killing one app mid-game returns the other to the lobby; engine test suite covers the whole rules table.

## M3 — Polish & the trick layer

- Preset trick list + free-text entry; attempt countdown timer (optional rule).
- Reconnect grace: rejoining a room within ~60 s resumes the game (stretch — cut if it drags).
- Camera clips of attempts (re-add `camera`): **record & show to peer** only, explicitly *not* a verification system. Decide scope with Architect before starting.

## M4 — Ship

- Deploy the relay to a free-tier host (Render / Fly.io / Railway), `wss://` with TLS, `PORT` from env.
- App identity: name, icon, splash; friendly error/empty states; README rewritten for humans.
- GitHub Actions CI: `flutter analyze` + `flutter test` on every push (uses the built-in `GITHUB_TOKEN`; your personal token is not involved).
- Internal testing track (Play Console) and/or TestFlight.

---

**Parking lot** (ideas we deliberately said "not yet" to): WebRTC true P2P (ADR-005) · accounts · match history · spectator mode · "last try" rule variant (engine flag exists, UI later).

**Parking lot additions (2026-09-02, Producer + Architect session):**
· Async "challenge mode" — public many-player S.K.A.T.E. seeded by shared
  clips (Twitter/social); letters tracked per challenge
· Ranked — live-witnessed attempts over WebRTC media (recorded clips
  cannot prove one-attempt; only a live window can). Attempt timer
  becomes the enforced rule in ranked only
· Spots/"gaps" map — Pokémon-Go-style discovery of real skate spots,
  lore-famous gaps as landmarks; shops; meetups
· Matchmaking + verified-pro flair (banners)
· Clip delivery in-app via WebRTC data channels (ADR-005)
· Hardware someday: tracking tripod for solo filming
