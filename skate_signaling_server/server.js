const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: 8080, host: '0.0.0.0' });

// Global State
const rooms = new Map(); // roomCode (number) -> [ws1, ws2]
const clients = new Map(); // ws -> { playerId, roomCode }
let nextPlayerId = 1;

function generateRoomCode() {
  let code;
  do {
    code = Math.floor(10000 + Math.random() * 90000); // 10000-99999
  } while (rooms.has(code));
  return code;
}

function hex(byte) {
  return `0x${byte.toString(16).padStart(2, '0').toUpperCase()}`;
}

function sendError(ws, code) {
  // Header: [version:1, opcode:1, senderId:2, payloadLen:1] -> [0x01, 0x0F, 0x00, 0x00, 0x01]
  const buf = Buffer.alloc(6);
  buf.writeUInt8(0x01, 0); // version
  buf.writeUInt8(0x0F, 1); // ERROR opcode
  buf.writeUInt16BE(0x0000, 2); // senderId (server)
  buf.writeUInt8(0x01, 4); // payloadLen
  buf.writeUInt8(code, 5); // error code
  ws.send(buf, { binary: true });
}

function sendPeerJoined(ws, peerId) {
  const buf = Buffer.alloc(7);
  buf.writeUInt8(0x01, 0); // version
  buf.writeUInt8(0x03, 1); // PEER_JOINED opcode
  buf.writeUInt16BE(0x0000, 2); // senderId (server)
  buf.writeUInt8(0x02, 4); // payloadLen
  buf.writeUInt16BE(peerId, 5); // the other player's id
  ws.send(buf, { binary: true });
}

function removeClientFromRoom(ws) {
  const state = clients.get(ws);
  if (!state || !state.roomCode) return;

  const room = rooms.get(state.roomCode);
  if (room) {
    const updatedRoom = room.filter(client => client !== ws);

    if (updatedRoom.length === 0) {
      rooms.delete(state.roomCode); // Room is empty, clean it up
    } else {
      rooms.set(state.roomCode, updatedRoom);

      // Send PEER_LEFT (0x04) to the remaining peer
      const peer = updatedRoom[0];
      if (peer.readyState === WebSocket.OPEN) {
        const buf = Buffer.alloc(7);
        buf.writeUInt8(0x01, 0); // version
        buf.writeUInt8(0x04, 1); // PEER_LEFT opcode
        buf.writeUInt16BE(0x0000, 2); // senderId
        buf.writeUInt8(0x02, 4); // payloadLen
        buf.writeUInt16BE(state.playerId, 5); // peerId that left
        peer.send(buf, { binary: true });
      }
    }
  }
  state.roomCode = null;
}

// Handles a JOIN (0x01) frame. Payload is already known to be 4 bytes.
function handleJoin(ws, message) {
  const requestedRoom = message.readUInt32BE(5);
  const state = clients.get(ws);

  // If already in a room, leave it gracefully first
  if (state.roomCode !== null) {
    removeClientFromRoom(ws);
  }

  let roomCode = requestedRoom;
  let role = 1; // 1 = creator, 2 = joiner

  if (roomCode === 0) {
    roomCode = generateRoomCode();
    rooms.set(roomCode, [ws]);
    role = 1;
  } else {
    const room = rooms.get(roomCode);
    if (!room) {
      sendError(ws, 0x02); // room not found
      return;
    }
    if (room.length >= 2) {
      sendError(ws, 0x01); // room full
      return;
    }
    room.push(ws);
    role = 2;
  }

  state.roomCode = roomCode;
  console.log(`[+] Player ${state.playerId} joined room ${roomCode} as role ${role}`);

  // Send JOINED (0x02) to the sender
  const joinedBuf = Buffer.alloc(12);
  joinedBuf.writeUInt8(0x01, 0); // version
  joinedBuf.writeUInt8(0x02, 1); // opcode
  joinedBuf.writeUInt16BE(0x0000, 2); // sender (server)
  joinedBuf.writeUInt8(0x07, 4); // payload len
  joinedBuf.writeUInt16BE(state.playerId, 5);
  joinedBuf.writeUInt32BE(roomCode, 7);
  joinedBuf.writeUInt8(role, 11);
  ws.send(joinedBuf, { binary: true });

  // The room is now full. PROTOCOL.md §5: PEER_JOINED goes to BOTH clients,
  // so each side learns the other's playerId and can seed its engine.
  if (role === 2) {
    const creatorWs = rooms.get(roomCode)[0];
    const creatorState = clients.get(creatorWs);
    if (creatorWs.readyState === WebSocket.OPEN) {
      sendPeerJoined(creatorWs, state.playerId);
    }
    if (creatorState) {
      sendPeerJoined(ws, creatorState.playerId);
    }
  }
}

// Forwards a game frame (0x10-0x2F) verbatim to the one other socket in the
// sender's room. Never echoed to the sender, never sent across rooms. The
// payload is never parsed — game meaning lives in the clients.
function forwardGameFrame(ws, message) {
  const state = clients.get(ws);
  if (!state || !state.roomCode) {
    console.log('[-] Dropping game frame: sender not in a room');
    sendError(ws, 0x04); // not in a room
    return;
  }

  const room = rooms.get(state.roomCode);
  if (!room) return;

  for (const client of room) {
    if (client !== ws && client.readyState === WebSocket.OPEN) {
      client.send(message, { binary: true });
    }
  }
}

wss.on('connection', function connection(ws) {
  console.log('[+] New client connected.');
  clients.set(ws, { playerId: nextPlayerId++, roomCode: null });

  ws.on('message', function incoming(message, isBinary) {
    if (!isBinary) {
      console.log('[-] Dropping non-binary message.');
      return;
    }

    // PROTOCOL.md §3 — validate in order, never index before checking length.
    if (message.length < 5) {
      console.log(`[-] Dropping packet: short packet (${message.length} B < 5 B header)`);
      if (message.length > 0) sendError(ws, 0x03); // malformed packet
      return;
    }

    const version = message.readUInt8(0);
    if (version !== 0x01) {
      console.log(`[-] Dropping packet: unsupported version ${hex(version)}`);
      return;
    }

    const opcode = message.readUInt8(1);
    const payloadLen = message.readUInt8(4);

    if (message.length !== 5 + payloadLen) {
      console.log(
        `[-] Dropping packet: length mismatch (got ${message.length} B, header says ${5 + payloadLen} B)`
      );
      sendError(ws, 0x03);
      return;
    }

    // PROTOCOL.md §4 — opcode ranges.
    if (opcode <= 0x0F) {
      // Control range: terminated here, never forwarded. Only JOIN is valid inbound.
      if (opcode !== 0x01) {
        console.log(`[-] Dropping inbound control opcode ${hex(opcode)}: only JOIN is valid`);
        return;
      }
      if (payloadLen !== 4) {
        console.log('[-] Dropping malformed JOIN: payload must be 4 bytes');
        sendError(ws, 0x03);
        return;
      }
      handleJoin(ws, message);
      return;
    }

    if (opcode <= 0x2F) {
      forwardGameFrame(ws, message);
      return;
    }

    console.log(`[-] Dropping packet: reserved opcode ${hex(opcode)}`);
  });

  ws.on('close', () => {
    console.log('[-] Client disconnected.');
    removeClientFromRoom(ws);
    clients.delete(ws);
  });

  ws.on('error', () => {
    removeClientFromRoom(ws);
    clients.delete(ws);
  });
});

console.log('skate_p2p Binary Relay Server listening on 0.0.0.0:8080');
