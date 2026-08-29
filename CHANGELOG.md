# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### M2-T2.2 — Protocol v1 game opcodes, end to end
- **Relay is strict v1.** Every inbound frame is validated per PROTOCOL.md §3 (version byte `0x01` required). Control opcodes `0x00–0x0F` terminate at the server and are never forwarded — only `JOIN` is valid inbound; game opcodes `0x10–0x2F` are forwarded verbatim to the one other socket in the sender's room, never echoed and never across rooms; `0x30+` is dropped and logged. The transitional first-byte legacy forwarding rule is deleted.
- `PEER_JOINED` (0x03) is now sent to **both** clients when a room fills (updated PROTOCOL.md §5), so each side learns the other's `playerId` and can seed an identical engine.
- Added the v1 game opcodes to `PacketCodec`: `TRICK_SET` (0x10, `nameLen` u8 + UTF-8 name, `nameLen == 0` = unnamed), `ATTEMPT_RESULT` (0x11, `0x00` bail / `0x01` land — any other value dropped and logged) and `REMATCH` (0x13, empty payload), with encoders for each.
- `PacketDispatcher` now treats every inbound frame as v1: control opcodes route to the `AppState` handlers, game opcodes to `AppState.applyRemoteEvent`. The legacy 0x02/0x03 path is gone and `binary_packer.dart` is deleted.
- `AppState` hosts the `GameState` engine snapshot. Local intents (`setTrick` / `reportResult` / `voteRematch`) apply to the engine first and only put a packet on the wire if the engine accepted the event; remote packets decode straight into the engine. Same events, same order, both engines agree (ADR-003).
- `PEER_LEFT` now feeds the engine a `PeerLeft` event before the reconnect-to-lobby flow runs.
- Removed `isMyTurn`, `localLetters` and `peerLetters` from `AppState` — the UI derives everything from `game` plus `playerId`.
- `MatchScreen` is functional on the engine: derived phase text, trick-name field + SET when you're the setter, LANDED/BAILED when the attempt is yours, per-player letters, game-over text and REMATCH. Visual polish is T2.3.
- Tests: codec fixtures and validation for all three game opcodes, dispatcher coverage of v1 control + game routing, a new `app_state_test.dart` that cross-feeds two `AppState`s to the same `gameOver` and rematch, and `rooms_smoke.js` extended to prove control frames are never forwarded, game frames never cross rooms or echo, and the joiner receives `PEER_JOINED`.

- Added the Room Lobby screen (`LobbyScreen`) with support for room creation and 5-digit room joining.
- Implemented `PacketCodec` for robust binary encoding/decoding of v1 control frames (`JOIN`, `JOINED`, `PEER_JOINED`, `PEER_LEFT`, and `ERROR`).
- Updated `PacketDispatcher` to branch on the first byte (0x01 is routed to v1 control frame decoding, other bytes use the legacy v0 path).
- Extended `AppState` with `ClientPhase` state machine (`disconnected`, `lobbyIdle`, `waitingForPeer`, `inMatch`) and identity fields (`playerId`, `roomCode`, `role`).
- Removed the hardcoded `1024` player ID for legacy score packets, dynamically using the server-assigned `playerId` instead.
- Implemented seamless reconnection and cleanup for canceling a match creation, leaving an ongoing match, or when a peer leaves.
- Added comprehensive unit tests for `PacketCodec` worked examples, malformed packet validation, and `PacketDispatcher` v1/v0 routing.

- Implemented `GameEngine` (`GameState`/`GameEvent`) as a pure Dart reducer covering the full S.K.A.T.E. rules table: role swaps on setter bail, phase transitions on land/bail, letter accumulation keyed to player identity (not seat/role), game-over detection, and rematch voting with role rotation.
- Added `game_engine_test.dart` covering every rules-table row, invalid/out-of-phase events, PeerLeft from every active phase, and an explicit regression test proving letters survive a role swap.

- Fixed `_copyWith` null-coalescing bug where `currentTrickName` was never cleared on phase transitions (caught by the rule tests).

- Unnamed tricks (empty name) are now legal, matching PROTOCOL.md §6; trick declaration is tracked separately from the trick's name.

### Client-Side Network & Reconnect Protocol
* **Reconnection & State Isolation:** Reconnection logic must use an injected callback wired via `main.dart` to maintain clean architectural layering. 
* **Stale Channel Safety:** `SignalingService` must explicitly ignore asynchronous callbacks and close events originating from stale or superseded socket connections to prevent race conditions during rapid state transitions.
