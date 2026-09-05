✦ REPORT M1-T1.2 — DONE
  CHANGED:
   - lib/core/network/packet_codec.dart (new +129 -0)
   - lib/ui/screens/lobby_screen.dart (new +310 -0)
   - test/packet_codec_test.dart (new +115 -0)
   - lib/core/network/packet_dispatcher.dart (+43 -17)
   - lib/core/state/app_state.dart (+112 -12)
   - lib/main.dart (+24 -9)
   - lib/ui/screens/match_screen.dart (+65 -22)
   - test/packet_dispatcher_test.dart (+170 -0)
   - CHANGELOG.md (+8 -0)
  CHECKS: analyze ✅  test ✅ (29 passed)
  COMMITS: feat(net): implement room lobby, player identity, and v1 control packet codec/dispatcher
  CHANGELOG: updated
  QUESTIONS/FLAGS: none
  ---
  Implementation Summary
   1. Room Lobby Screen (LobbyScreen): Added a beautiful, cohesive dark-themed lobby screen allowing users to:
      - Create a room via server-issued binary JOIN (0x01 with roomCode = 0).
      - Enter a 5-digit room code with numeric restriction (digits only) to join an existing game.
      - Cancel a pending lobby creation with seamless state reset.
      - Display inline status/errors (e.g. Room full, Room not found) without disturbing the flow.
   2. v1 Control Frame Packet Codec (PacketCodec): Added a robust codec that parses server control frames (JOINED, PEER_JOINED, PEER_LEFT, ERROR) and encodes outbound client requests (JOIN). Complies fully with PROTOCOL.md §3
      (strict payload length validation, version checks, unknown frame dropping) and prevents any crash.
   3. Packet Dispatcher Refactoring (PacketDispatcher): Integrated a clean first-byte routing strategy. Messages starting with 0x01 are successfully decoded via PacketCodec as v1 control frames. Any other starting byte falls back seamlessly to the legacy v0 pathway, avoiding any regressions.
   4. Dynamic Player Identity & Connection State (AppState): Exterminated the hardcoded 1024 player ID! The app now saves the server-allocated playerId upon receipt of JOINED and uses it as the source senderId for score
      packets. App state introduces a robust ClientPhase state machine (disconnected, lobbyIdle, waitingForPeer, inMatch) that handles UI screen switches natively without risky navigator pops.
   5. Reconnection & Cleanup Loop: Implemented a reconnection loop via AppState callback. Tapping Cancel, leaving an ongoing match, or receiving PEER_LEFT executes a clean socket disconnection and connection reload—resetting
      local scores and player identities to land cleanly back on lobbyIdle with an inline notice banner.
   6. Extensive Test Coverage: Extended the test suite with comprehensive unit tests in test/packet_codec_test.dart and test/packet_dispatcher_test.dart to verify protocol fixtures, worked examples, error handling, truncation
      resilience, and correct dispatcher routing. All 29 unit tests pass and flutter analyze is completely clean of any warnings or lint issues.
