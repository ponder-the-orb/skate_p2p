# skate_p2p Binary Protocol — v1

**This file is the single source of truth for the wire format.** If code and this document disagree, the code is wrong.
Changes to this file require Architect sign-off *before* implementation, and client + server must be updated in the same milestone.

**Status:** SPEC (implemented at M2). The code currently on `main` speaks the legacy v0 format described in Appendix A; v0 is retired when M2 ships.

---

## 1. Transport rules

- Transport is **WebSocket**, binary frames only. Text frames are dropped and logged by every receiver.
- **One WebSocket message = one packet.** No stream framing is needed (WebSocket preserves message boundaries). If a non-message transport is ever reintroduced, length-prefix framing becomes mandatory — see ADR-001.
- **All multi-byte integers are big-endian.** (This is Dart `ByteData`'s default and Node's `readUInt16BE` family. Never use the `LE` variants.)

## 2. Header — every packet, 5 bytes

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 1 | `version` | Always `0x01` for this spec |
| 1 | 1 | `opcode` | See tables below |
| 2 | 2 | `senderId` | uint16, big-endian. Server-assigned. `0x0000` = server, or a client that has not yet received `JOINED` |
| 4 | 1 | `payloadLen` | Number of payload bytes following the header (0–255) |

Total packet size = `5 + payloadLen`.

## 3. Validation — every receiver MUST, in order

1. `length >= 5`, else **drop + log**. Never index into a buffer before this check.
2. `version == 0x01`, else drop + log (`unsupported version`).
3. `length == 5 + payloadLen`, else drop + log (`length mismatch`).
4. `opcode` is known and its payload length matches this spec, else drop + log (`unknown/malformed opcode`).

**A malformed packet must never crash a client or the server.** Drop, log, continue.

## 4. Opcode ranges

| Range | Class | Handling |
|---|---|---|
| `0x00–0x0F` | **Control** | Terminated by the server (or sent by it). Never forwarded. |
| `0x10–0x2F` | **Game** | Forwarded verbatim by the server to the *other* client in the sender's room. **Never echoed to the sender. Never sent across rooms.** |
| `0x30–0xFF` | Reserved | Unknown opcodes are dropped + logged. |

## 5. Control opcodes

### `0x01 JOIN` (client → server) — payload 4 bytes
| Offset | Size | Field |
|---|---|---|
| 5 | 4 | `roomCode` uint32 — `0` = create a new room; otherwise join this room |

### `0x02 JOINED` (server → client) — payload 7 bytes
| Offset | Size | Field |
|---|---|---|
| 5 | 2 | `playerId` uint16 — your assigned id; use it as `senderId` from now on |
| 7 | 4 | `roomCode` uint32 — server-generated for creates: random decimal 10000–99999, shown to the user as digits |
| 11 | 1 | `role` — `1` = you set first (room creator), `2` = you defend first |

### `0x03 PEER_JOINED` (server → client) — payload 2 bytes
`peerId` uint16. Sent to BOTH clients when the room becomes full: to the
creator when the second player joins, and to the joiner immediately after
its JOINED. Each side thereby learns the other's playerId. Game may begin.

### `0x04 PEER_LEFT` (server → client) — payload 2 bytes
`peerId` uint16. The engine transitions to `abandoned`.

### `0x0F ERROR` (server → client) — payload 1 byte
| Code | Meaning |
|---|---|
| `0x01` | room full |
| `0x02` | room not found |
| `0x03` | malformed packet |
| `0x04` | not in a room (game opcode before JOINED) |

### `0x05 PEER_DISCONNECTED` (server → client) — payload 4 bytes
| Offset | Size | Field |
|---|---|---|
| 5 | 2 | `peerId` uint16 |
| 7 | 2 | `graceSeconds` uint16 — how long the room will wait |

Your peer's socket dropped, but the room is in **reconnect grace**: it
lingers for `graceSeconds` awaiting their return. The game is NOT
abandoned. UI shows a reconnecting state and may count down from
`graceSeconds`. The duration is a server-side constant (v1: 120),
announced on the wire so clients never hardcode it.

### `0x06 PEER_RECONNECTED` (server → client) — payload 2 bytes
`peerId` uint16. Sent to BOTH clients when a graced room becomes whole
again. The client with a game in progress (the survivor) responds by
sending `STATE_SYNC 0x12`. The freshly joined client sets its peerId,
enters an awaiting-sync state, and waits for that packet.

### Reconnect grace (server rules)
- A room whose socket closes while a peer remains enters grace for a server-configured window (v1: 120 s), announced via 0x05;
  the vacant slot remembers its playerId and role.
- A JOIN carrying that room's code during grace re-seats the vacant
  slot with the ORIGINAL playerId and role; JOINED is sent as normal,
  then PEER_RECONNECTED to both. PEER_JOINED is never re-sent — it
  strictly means a NEW game's room became full.
- Grace expiry → PEER_LEFT to the survivor (engine → abandoned) and
  the room is deleted. A room whose LAST connected socket closes is
  deleted immediately — grace exists only while one peer remains.

## 6. Game opcodes

Context (whose result this is, what trick is active) is derived from the GameEngine phase — see ARCHITECTURE.md §5. That's why these payloads are so small.

### `0x10 TRICK_SET` (setter → defender) — payload 1 + N bytes
| Offset | Size | Field |
|---|---|---|
| 5 | 1 | `nameLen` uint8 (0–254) |
| 6 | N | UTF-8 trick name. `nameLen == 0` is legal → "unnamed trick" |

Sent when the setter declares the trick they're about to attempt.

### `0x11 ATTEMPT_RESULT` (attempting player → other player) — payload 1 byte
`0x00` = bailed, `0x01` = landed. In phase `setting` this is the setter's result; in phase `defending`, the defender's. Any other value → drop + log.

### `0x12 STATE_SYNC` (survivor → rejoiner) — payload 17 + N bytes
Full game-state snapshot, sent once upon receiving PEER_RECONNECTED
by the client whose game is in progress. Forwarded like any game
opcode. A client accepts 0x12 ONLY while awaiting sync; otherwise
drop + log.

| Offset | Size | Field |
|---|---|---|
| 5  | 1 | `phase` — 1 setting · 2 defending · 3 gameOver |
| 6  | 2 | `setterId` uint16 |
| 8  | 2 | `defenderId` uint16 |
| 10 | 2 | `firstSetterId` uint16 |
| 12 | 2 | `winnerId` uint16 — `0` = none (playerIds are never 0) |
| 14 | 2 | `playerA` uint16 |
| 16 | 1 | `lettersA` 0–5 |
| 17 | 2 | `playerB` uint16 |
| 19 | 1 | `lettersB` 0–5 |
| 20 | 1 | `flags` — bit0 trickDeclared · bit1 A voted rematch · bit2 B voted |
| 21 | 1 | `nameLen` uint8 (0–234) |
| 22 | N | UTF-8 trick name |

Validation per §3; any out-of-range enum or letter count → drop + log.

### `0x13 REMATCH` (client → client) — payload 0 bytes
Vote for a rematch. The game resets only when the engine has seen a REMATCH from **both** players.

## 7. Worked examples (hex)

`JOIN`, create a new room, before an id is assigned:
```
01 01 00 00 04 00 00 00 00
ver op sender  len roomCode=0
```

`JOINED`: you are player 7, room 41235, you set first:
```
01 02 00 00 07 00 07 00 00 A1 13 01
ver op sender=0 len=7 playerId=7 roomCode=41235 role=1
```

`ATTEMPT_RESULT` — player 7 landed it:
```
01 11 00 07 01 01
ver op sender=7 len=1 landed
```

## 8. Change control

1. Propose the change in a ticket report (implementers **never** change the wire format unprompted).
2. Architect updates this file first; the version byte bumps only for breaking changes.
3. Client codec, client dispatcher, server, and tests all land in the same milestone.
4. CHANGELOG entry references the protocol change explicitly.

---

## Appendix A — Legacy v0 (current code, retired at M2)

For the record only. No version byte; 4-byte header `[opcode][senderId:2][payloadLen:1]`; `senderId` hardcoded to `1024`.

| Opcode | Size | Meaning | Known defects |
|---|---|---|---|
| `0x01` handshake | 6 B | built & parsed, then ignored | dead code |
| `0x02` score | 5 B | letter count | the two screens disagree on whose letters the field means (ARCHITECTURE.md, Known Issue #6) |
| `0x03` turn | 5 B | `isMyTurn` flag | works only via accidental double negation; desyncs under relay echo (Known Issue #5) |

### Transitional server rule — M1 only (retired at M2)
Until v1 ships end-to-end, the server disambiguates by first byte:
- 0x01 → v1 control frame (only JOIN is valid from clients); validate per §3.
- anything else → legacy v0 game frame: forwarded verbatim to the other
  socket in the sender's room; never parsed, never echoed, never cross-room.
This works because the v0 handshake (first byte 0x01) was deleted in M0.
Strict §4 termination of 0x00–0x0F begins at M2.

### Transitional client rule — M1 only (retired at M2)
Client side of the same rule: an inbound frame whose first byte is 0x01
is a v1 control frame from the server (JOINED / PEER_JOINED / PEER_LEFT
/ ERROR — validate per §3); any other first byte is a legacy v0 game
frame (0x02 / 0x03) and takes the old dispatcher path. Unambiguous for
the same reason: the v0 handshake (opcode 0x01) was deleted in M0, and
clients never receive v1 game opcodes before M2.
