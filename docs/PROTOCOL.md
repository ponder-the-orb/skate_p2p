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
`peerId` uint16. Sent to the creator when the second player joins. Game may begin.

### `0x04 PEER_LEFT` (server → client) — payload 2 bytes
`peerId` uint16. The engine transitions to `abandoned`.

### `0x0F ERROR` (server → client) — payload 1 byte
| Code | Meaning |
|---|---|
| `0x01` | room full |
| `0x02` | room not found |
| `0x03` | malformed packet |
| `0x04` | not in a room (game opcode before JOINED) |

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

### `0x12` — reserved (`SCORE_SYNC`)
Reserved for a future explicit resync. Not implemented in v1; the deterministic engine makes it unnecessary. Do not use.

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
