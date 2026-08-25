# TICKET M0 — Stabilize

*(Paste this to Phil verbatim. It covers all of milestone M0 as one session; if it runs long, T0.1–T0.4 first, T0.5–T0.6 as a second session.)*

---

Read `GEMINI.md` at the repo root, then `docs/ARCHITECTURE.md` (at least §7–8), `docs/PROTOCOL.md §3`, and `docs/WORKFLOW.md §3–5` before starting.

**GOAL:** One transport, no crashes on bad input, no ghost traffic. No new features.

**BRANCH:** `m0/stabilize` → PR into `main` when done.

**TASKS:**

- **T0.1** — Delete `lib/core/network/network_service.dart` and the HOST/CONNECT buttons + related wiring in `main.dart`. The app's only transport is the WebSocket path (`SignalingService`). Point `main.dart` at the match screen flow. Delete, don't comment out — git history keeps it. *(ADR-001)*
- **T0.2** — `server.js`: in the broadcast loop, never send back to the originating socket (`client !== ws` guard). *(Fixes Known Issue #2 — the echo bug.)*
- **T0.3** — `PacketDispatcher`: before reading any field, validate — non-empty, length ≥ header size, and total length matches the expected size for that opcode. Bad packets: log and return, never throw. *(Apply the discipline of PROTOCOL.md §3 to the current v0 format.)*
- **T0.4** — Remove the hardcoded test packet sent on connect in `SignalingService`, and remove the dead handshake (0x01) pack/parse code.
- **T0.5** — Create `test/`: (a) BinaryPacker round-trip tests — pack each packet type, parse it back, assert every field; (b) dispatcher fed truncated and garbage buffers logs and does not throw.
- **T0.6** — Remove `camera` from `pubspec.yaml`. *(ADR-007 — re-added at M3.)*

**ACCEPTANCE:**
- Two clients through the relay: no echo (sender's own state never flickers on send), scores update on the peer only.
- Feeding the dispatcher `[0x02]`, `[]`, and 20 random bytes logs and continues.
- `flutter analyze` clean, `flutter test` green, `dart format` applied.
- `CHANGELOG.md` created (Keep-a-Changelog style) with entries for the above.
- Conventional commits, then reply with the five-line report from `docs/WORKFLOW.md §4`, including the GitHub compare link.

**OUT OF SCOPE:** Rooms, player IDs, protocol v1, any UI beyond removing the dead buttons. That's M1/M2 — resist.
