# skate_p2p Memory Map & Binary Protocol Specification (v1.0)

## Design Principles
- **Big-endian (Network byte order)** for cross-platform stability.
- **Fixed-size headers** to avoid dynamic string parsing.
- **Binary serialization** (`Uint8List` / `Buffer`) to ensure maximum network efficiency.

## 1. Packet Structure (Header + Payload)
Every packet transmitted over the WebSocket consists of a fixed **4-byte header** followed by a variable **payload body**.

### Header Layout (4 Bytes Total)
| Offset | Field Name | Type | Description |
| :--- | :--- | :--- | :--- |
| `0` | `PacketType` | `Uint8` | Defines the command/action. |
| `1-2` | `SenderID` | `Uint16` | Unique numeric identifier for the client session. |
| `3` | `PayloadLength`| `Uint8` | Length of the payload body (in bytes). |

### Opcode Registry
| Opcode | Description | Payload Size |
| :--- | :--- | :--- |
| `0x01` | Handshake/Registration | 2 bytes (Uint16) |
| `0x02` | Game State / Score Update | 1 byte (Uint8: 0-5) |
| `0x03` | Spot Marker / GPS Telemetry | TBD |
| `0x04` | Trick Log / Session Telemetry| TBD |

---

## 2. Test-Driven Development (TDD) Vectors

### Vector 1: Client Registration (Opcode 0x01)
* **Goal:** Verify Flutter-to-Server registration packets.
* **Input:** `PacketType=0x01`, `SenderID=1024`, `Payload=5`.
* **Byte Array:** `[0x01, 0x04, 0x00, 0x02, 0x00, 0x05]` (6 bytes total).
* **Assertion:** Node.js server confirms read values match input.

### Vector 2: Game State Update (Opcode 0x02)
* **Goal:** Verify S-K-A-T-E score synchronization.
* **Input:** `PacketType=0x02`, `SenderID=1024`, `Payload=3`.
* **Byte Array:** `[0x02, 0x04, 0x00, 0x01, 0x03]` (5 bytes total).
* **Assertion:** Server relays buffer to peer intact.
```[cite: 1]

**2. Create the Architecture Design Document**
Create a file named `ADD.md` in your project root and paste this into it:
```markdown
# skate_p2p: Architecture Design Document (ADD)

## 1. System Philosophy
This system adheres to a strict separation of concerns. The network layer must never touch the UI, and the UI must never parse network bytes. Data moves in one direction: 
**Network Socket → Binary Parser → State Engine → UI Widgets.**

## 2. The Core Components

### A. The Dumb Relay (Node.js Server)
The server remains entirely agnostic to game logic. It does not know the rules of S-K-A-T-E or what a video stream is.
* **Role:** Connection management and raw binary broadcasting.
* **Mechanic:** Reads `Byte 0` (Opcode) and `Byte 3` (Payload Length). If the Opcode is intended for a peer, it takes the raw `Buffer` and pipes it directly to the recipient socket. Zero JSON parsing. Zero state storage.

### B. The Client State Engine (Flutter)
Flutter is inherently object-oriented, which can clash with Data-Oriented Design if you aren't careful. To maintain bare-metal efficiency, we isolate the application state from the widget tree.

* **The Network Boundary:** A dedicated `SocketManager` class listens to the WebSocket. It receives raw `Uint8List` byte arrays and passes them immediately to the `PacketDispatcher`.
* **The Packet Dispatcher (The Switchboard):** This is where modularity lives. The dispatcher reads `Byte 0` (the Opcode) and hands the payload to the correct internal handler (e.g., `Opcode 0x02` goes to the `SkateGameHandler`). 
* **The Flat State:** Game state (like S-K-A-T-E scores) is kept in flat, primitive variables (integers, booleans). We do not create massive nested objects. 

### C. The WebRTC Video Gateway
Video cannot be sent over the same WebSocket pipe as our binary game state—it would choke the connection immediately. 
* **The Split:** The WebSocket handles *Signaling* (the handshake, exchanging connection keys) and *Game State* (Opcode `0x02`).
* **The P2P Mesh:** Once the WebSocket establishes the handshake, the devices open a secondary, direct WebRTC channel strictly for pushing raw camera frames peer-to-peer.

---

## 3. Modular Directory Structure (Flutter)
```text
lib/
├── main.dart
├── core/
│   ├── network/
│   │   ├── socket_manager.dart     # Manages the WebSocket and ADB tunnel connection
│   │   ├── binary_packer.dart      # Utility to write Uint8Lists (headers + payload)
│   │   └── packet_dispatcher.dart  # The Opcode switch-case statement
│   └── state/
│       └── app_state.dart          # Holds the flat variables (e.g., int localLetters, int peerLetters)
├── features/
│   ├── signaling/                  
│   │   └── webrtc_manager.dart     # Handles camera bindings and direct video streams
│   ├── skate_game/
│   │   ├── logic.dart              # The S-K-A-T-E rules engine (updates AppState)
│   │   └── widgets/                # UI elements showing the letters
│   └── [FUTURE] map_spots/         # Isolated folder for future AR maps
└── ui/
    ├── screens/
    │   └── match_screen.dart       # The main UI tying the camera and game widgets together
    └── theme/                      # Global colors, fonts, styling

