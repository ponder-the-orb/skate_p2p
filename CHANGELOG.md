# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### M3-T3.1 — Preset trick list
- New `lib/ui/data/trick_presets.dart`: one `const List<String> trickPresets` of 23 common street tricks, ordered roughly easy → hard. It lives under `ui/` because it is picker content, not a rule — the engine, the codec and the relay are untouched by this ticket.
- `MatchScreen` state 1 (I'm the setter, nothing declared) gains a horizontally scrollable chip row above the trick field. Tapping a chip **fills** the field and leaves it editable; SET remains the single path that declares a trick. Chips never appear in any other state.
- Free-text entry is unchanged, including the empty name that reads as "Unnamed trick" (PROTOCOL.md §6).
- Tests: `trick_presets_test.dart` pins the list as non-empty, blank-free, duplicate-free, and every name at most 254 UTF-8 bytes — the `nameLen` uint8 ceiling of `TRICK_SET`. `match_screen_test.dart` state 1 gains chip rendering, tap-fills-the-field-without-declaring, SET-after-a-tap declaring that exact name, and a filled preset still being editable; state 2 asserts the chips are gone.

### M2-T2.3 — Match screen polish
- `MatchScreen` rebuilt around the seven states of a match, each one readable at arm's length: setter with nothing declared (trick field + SET, an empty name still legal and shown as "Unnamed trick"), setter with a trick declared (the trick + LANDED / BAILED), the peer setting (waiting, opponent marked **UP**), defending as either player (their trick, big, + LANDED / BAILED for the defender), the game-over overlay, and the existing lobby-return on `abandoned`.
- Letters now render as an accumulating S·K·A·T·E track per player; the most recently gained letter is filled red so a new letter is impossible to miss. No animation dependencies.
- Game over is a full-screen overlay: WIN / LOSE, the final letters for both players, and a REMATCH button that becomes "Waiting for opponent…" once this player has voted. A peer who votes first is announced ("Opponent wants a rematch").
- Dark palette local to the match screen; the leave-match affordance stays reachable from the top bar and the overlay.
- `LobbyScreen`: the notice and error panels share the match screen's bordered-panel styling (labelled `HEADS UP` / `ERROR`). Styling only — no behaviour change.
- The UI still reads only `AppState.game` plus `playerId`/`peerId`; no rule moved into a widget (ARCHITECTURE.md §3).
- Tests: `match_screen_test.dart` drives a real `AppState` through its public handlers and intents into each of states 1–6 and asserts the controls and text on screen. No mocks, no test-only setters.

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
