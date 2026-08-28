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

### Client-Side Network & Reconnect Protocol
* **Reconnection & State Isolation:** Reconnection logic must use an injected callback wired via `main.dart` to maintain clean architectural layering. 
* **Stale Channel Safety:** `SignalingService` must explicitly ignore asynchronous callbacks and close events originating from stale or superseded socket connections to prevent race conditions during rapid state transitions.
