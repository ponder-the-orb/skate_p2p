const WebSocket = require('ws');

const PORT = Number(process.env.PORT) || 8080;

// Reconnect grace (PROTOCOL.md §5). A room whose socket closes while a peer
// remains lingers this long, holding the vacant seat's playerId and role.
// The env override exists so tests can run the window in milliseconds.
const GRACE_MS = Number(process.env.GRACE_MS) || 120000;
const GRACE_SECONDS = Math.min(65535, Math.max(1, Math.ceil(GRACE_MS / 1000)));

const wss = new WebSocket.Server({ port: PORT, host: '0.0.0.0' });

// Global State
// roomCode (number) -> { sockets: [ws], vacant: {playerId, role} | null, graceTimer }
const rooms = new Map();
const clients = new Map(); // ws -> { playerId, roomCode, role }
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

// Builds a server-sourced control frame: senderId is always 0x0000 (§2).
function controlFrame(opcode, payload) {
  const buf = Buffer.alloc(5 + payload.length);
  buf.writeUInt8(0x01, 0); // version
  buf.writeUInt8(opcode, 1); // opcode
  buf.writeUInt16BE(0x0000, 2); // senderId (server)
  buf.writeUInt8(payload.length, 4); // payloadLen
  Buffer.from(payload).copy(buf, 5);
  return buf;
}

function send(ws, frame) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(frame, { binary: true });
  }
}

function sendError(ws, code) {
  send(ws, controlFrame(0x0f, [code]));
}

function sendPeerJoined(ws, peerId) {
  const payload = Buffer.alloc(2);
  payload.writeUInt16BE(peerId, 0);
  send(ws, controlFrame(0x03, payload));
}

function sendPeerLeft(ws, peerId) {
  const payload = Buffer.alloc(2);
  payload.writeUInt16BE(peerId, 0);
  send(ws, controlFrame(0x04, payload));
}

// 0x05 PEER_DISCONNECTED — peerId + the grace window, announced on the wire
// so clients never hardcode the duration (PROTOCOL.md §5).
function sendPeerDisconnected(ws, peerId, graceSeconds) {
  const payload = Buffer.alloc(4);
  payload.writeUInt16BE(peerId, 0);
  payload.writeUInt16BE(graceSeconds, 2);
  send(ws, controlFrame(0x05, payload));
}

function sendPeerReconnected(ws, peerId) {
  const payload = Buffer.alloc(2);
  payload.writeUInt16BE(peerId, 0);
  send(ws, controlFrame(0x06, payload));
}

function clearGrace(room) {
  if (room.graceTimer !== null) {
    clearTimeout(room.graceTimer);
    room.graceTimer = null;
  }
}

// Grace ran out: the survivor is told PEER_LEFT (its engine abandons) and the
// room is deleted. Never fires for a room that is already gone — the timer is
// cleared on rejoin and on the survivor's own socket closing.
function expireGrace(roomCode) {
  const room = rooms.get(roomCode);
  if (!room || room.vacant === null) return;

  const lostId = room.vacant.playerId;
  room.graceTimer = null;
  room.vacant = null;
  rooms.delete(roomCode);

  for (const socket of room.sockets) {
    const state = clients.get(socket);
    if (state) state.roomCode = null;
    sendPeerLeft(socket, lostId);
  }
  console.log(`[-] Room ${roomCode}: grace expired for player ${lostId}; room deleted`);
}

// Takes [ws] out of its room. `grace` is true only for a socket that dropped
// (close/error): if a peer remains, the room enters reconnect grace instead of
// ending. A deliberate re-JOIN elsewhere keeps the old PEER_LEFT behaviour.
function removeClientFromRoom(ws, { grace = false } = {}) {
  const state = clients.get(ws);
  if (!state || state.roomCode === null) return;

  const roomCode = state.roomCode;
  const room = rooms.get(roomCode);
  state.roomCode = null;

  if (!room) return;

  room.sockets = room.sockets.filter((client) => client !== ws);

  // A room whose LAST connected socket closes is deleted immediately — grace
  // exists only while one peer remains (§5). This is also the survivor-leaves-
  // during-grace case: the timer dies with the room, so it can never fire late.
  if (room.sockets.length === 0) {
    clearGrace(room);
    rooms.delete(roomCode);
    console.log(`[-] Room ${roomCode} deleted: no sockets left`);
    return;
  }

  const peer = room.sockets[0];

  if (!grace) {
    sendPeerLeft(peer, state.playerId);
    return;
  }

  room.vacant = { playerId: state.playerId, role: state.role };
  room.graceTimer = setTimeout(() => expireGrace(roomCode), GRACE_MS);
  sendPeerDisconnected(peer, state.playerId, GRACE_SECONDS);
  console.log(
    `[~] Room ${roomCode}: player ${state.playerId} dropped; holding seat for ${GRACE_MS} ms`
  );
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
  let rejoined = false;

  if (roomCode === 0) {
    roomCode = generateRoomCode();
    rooms.set(roomCode, { sockets: [ws], vacant: null, graceTimer: null });
    role = 1;
  } else {
    const room = rooms.get(roomCode);
    if (!room) {
      sendError(ws, 0x02); // room not found
      return;
    }
    if (room.vacant !== null) {
      // Reconnect grace: whoever holds the code re-seats the vacant slot with
      // its ORIGINAL playerId and role (§5 trust model — no auth by design).
      clearGrace(room);
      state.playerId = room.vacant.playerId;
      role = room.vacant.role;
      room.vacant = null;
      room.sockets.push(ws);
      rejoined = true;
    } else if (room.sockets.length >= 2) {
      sendError(ws, 0x01); // room full
      return;
    } else {
      room.sockets.push(ws);
      role = 2;
    }
  }

  state.roomCode = roomCode;
  state.role = role;
  console.log(
    `[+] Player ${state.playerId} ${rejoined ? 'rejoined' : 'joined'} room ${roomCode} as role ${role}`
  );

  // Send JOINED (0x02) to the sender
  const joinedBuf = Buffer.alloc(12);
  joinedBuf.writeUInt8(0x01, 0); // version
  joinedBuf.writeUInt8(0x02, 1); // opcode
  joinedBuf.writeUInt16BE(0x0000, 2); // sender (server)
  joinedBuf.writeUInt8(0x07, 4); // payload len
  joinedBuf.writeUInt16BE(state.playerId, 5);
  joinedBuf.writeUInt32BE(roomCode, 7);
  joinedBuf.writeUInt8(role, 11);
  send(ws, joinedBuf);

  const room = rooms.get(roomCode);

  if (rejoined) {
    // PEER_RECONNECTED (0x06) to BOTH; PEER_JOINED is never re-sent — it
    // strictly means a NEW game's room became full (§5).
    for (const socket of room.sockets) {
      const peer = room.sockets.find((other) => other !== socket);
      const peerState = peer ? clients.get(peer) : null;
      if (peerState) sendPeerReconnected(socket, peerState.playerId);
    }
    return;
  }

  // The room is now full. PROTOCOL.md §5: PEER_JOINED goes to BOTH clients,
  // so each side learns the other's playerId and can seed its engine.
  if (role === 2) {
    const creatorWs = room.sockets[0];
    const creatorState = clients.get(creatorWs);
    sendPeerJoined(creatorWs, state.playerId);
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

  // Mid-grace there is nobody to forward to. Dropped and logged — not an
  // ERROR: the sender IS in a room, its peer is merely away.
  if (room.vacant !== null) {
    console.log(`[-] Dropping game frame: room ${state.roomCode} peer slot is vacant`);
    return;
  }

  for (const client of room.sockets) {
    if (client !== ws) {
      send(client, message);
    }
  }
}

wss.on('connection', function connection(ws) {
  console.log('[+] New client connected.');
  clients.set(ws, { playerId: nextPlayerId++, roomCode: null, role: null });

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
    removeClientFromRoom(ws, { grace: true });
    clients.delete(ws);
  });

  ws.on('error', () => {
    removeClientFromRoom(ws, { grace: true });
    clients.delete(ws);
  });
});

console.log(
  `skate_p2p Binary Relay Server listening on 0.0.0.0:${PORT} (reconnect grace ${GRACE_MS} ms)`
);
