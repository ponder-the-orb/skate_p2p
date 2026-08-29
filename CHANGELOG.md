# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
