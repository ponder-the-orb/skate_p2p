const WebSocket = require('ws');

const PORT = 8080;

function connect() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${PORT}`);
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

function waitFor(ws, opcode) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`timed out waiting for opcode 0x${opcode.toString(16)}`)),
      2000
    );
    const handler = (msg) => {
      if (msg.readUInt8(0) === 0x01 && msg.readUInt8(1) === opcode) {
        clearTimeout(timer);
        ws.removeListener('message', handler);
        resolve(msg);
      }
    };
    ws.on('message', handler);
  });
}

// Records every frame a socket receives from here on, so we can assert on
// what did NOT arrive.
function recorder(ws) {
  const seen = [];
  ws.on('message', (msg) => seen.push(Buffer.from(msg)));
  return seen;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function assert(condition, message) {
  if (!condition) throw new Error(`FAIL: ${message}`);
}

function joinFrame(roomCode) {
  const buf = Buffer.alloc(9);
  buf.set([0x01, 0x01, 0x00, 0x00, 0x04], 0);
  buf.writeUInt32BE(roomCode, 5);
  return buf;
}

// TRICK_SET (0x10), unnamed — PROTOCOL.md §7 fixture shape.
function trickSetFrame(senderId) {
  const buf = Buffer.alloc(6);
  buf.set([0x01, 0x10], 0);
  buf.writeUInt16BE(senderId, 2);
  buf.writeUInt8(0x01, 4);
  buf.writeUInt8(0x00, 5);
  return buf;
}

// Any opcode with an arbitrary payload, correctly framed per §2.
function controlFrame(opcode, senderId, payload) {
  const buf = Buffer.alloc(5 + payload.length);
  buf.writeUInt8(0x01, 0);
  buf.writeUInt8(opcode, 1);
  buf.writeUInt16BE(senderId, 2);
  buf.writeUInt8(payload.length, 4);
  Buffer.from(payload).copy(buf, 5);
  return buf;
}

async function run() {
  console.log('🚀 Running rooms smoke test...\n');

  // 1. Room A: P1 creates, P2 joins. PEER_JOINED goes to BOTH (§5).
  const p1 = await connect();
  p1.send(joinFrame(0), { binary: true });
  const joined1 = await waitFor(p1, 0x02);
  const roomA = joined1.readUInt32BE(7);
  const p1Id = joined1.readUInt16BE(5);
  console.log(`✅ P1 created room: ${roomA}`);

  const p2 = await connect();
  const p1PeerJoined = waitFor(p1, 0x03);
  const p2PeerJoined = waitFor(p2, 0x03);
  p2.send(joinFrame(roomA), { binary: true });
  const joined2 = await waitFor(p2, 0x02);
  const p2Id = joined2.readUInt16BE(5);

  const p1Sees = await p1PeerJoined;
  assert(p1Sees.readUInt16BE(5) === p2Id, 'creator PEER_JOINED must carry the joiner id');
  console.log(`✅ P2 joined room ${roomA}; creator notified of peer ${p2Id}`);

  const p2Sees = await p2PeerJoined;
  assert(p2Sees.readUInt16BE(5) === p1Id, 'joiner PEER_JOINED must carry the creator id');
  console.log(`✅ Joiner also receives PEER_JOINED (peer ${p1Id})`);

  // 2. Third client into a full room is rejected.
  const p3 = await connect();
  p3.send(joinFrame(roomA), { binary: true });
  const errFull = await waitFor(p3, 0x0F);
  assert(errFull.readUInt8(5) === 0x01, 'expected ERROR room full');
  console.log('✅ P3 rejected: Room full');

  // 3. Room B, so we can prove game frames never cross rooms.
  const p5 = await connect();
  p5.send(joinFrame(0), { binary: true });
  const joined5 = await waitFor(p5, 0x02);
  const roomB = joined5.readUInt32BE(7);
  const p6 = await connect();
  const p5PeerJoined = waitFor(p5, 0x03);
  p6.send(joinFrame(roomB), { binary: true });
  await waitFor(p6, 0x02);
  await p5PeerJoined;
  console.log(`✅ Second room live: ${roomB}`);

  // 4. Unknown room code is rejected (a code neither room is using).
  let missingCode = 99999;
  while (missingCode === roomA || missingCode === roomB) missingCode--;
  const p4 = await connect();
  p4.send(joinFrame(missingCode), { binary: true });
  const errNotFound = await waitFor(p4, 0x0F);
  assert(errNotFound.readUInt8(5) === 0x02, 'expected ERROR room not found');
  console.log('✅ P4 rejected: Room not found');

  // From here on, record everything the four in-room sockets receive.
  const seen1 = recorder(p1);
  const seen2 = recorder(p2);
  const seen5 = recorder(p5);
  const seen6 = recorder(p6);

  // 5. Game frames: forwarded to the peer only. Never echoed, never cross-room.
  const trick = trickSetFrame(p1Id);
  p1.send(trick, { binary: true });
  await sleep(250);

  assert(seen2.length === 1, `peer should receive exactly one frame, got ${seen2.length}`);
  assert(seen2[0].equals(trick), 'game frame must be forwarded verbatim');
  assert(seen1.length === 0, 'game frame must never be echoed to its sender');
  assert(
    seen5.length === 0 && seen6.length === 0,
    'game frames must never cross rooms'
  );
  console.log('✅ Game frames forwarded verbatim to the peer only');
  console.log('✅ Game frames never echoed, never cross rooms');

  seen2.length = 0;

  // 6. Control frames terminate at the server — even valid-looking ones.
  const peerJoinedFromClient = controlFrame(0x03, p1Id, [0x00, 0x63]);
  const peerLeftFromClient = controlFrame(0x04, p1Id, [0x00, 0x63]);
  const errorFromClient = controlFrame(0x0f, p1Id, [0x01]);
  p1.send(peerJoinedFromClient, { binary: true });
  p1.send(peerLeftFromClient, { binary: true });
  p1.send(errorFromClient, { binary: true });
  await sleep(250);

  assert(seen2.length === 0, 'control frames must never be forwarded');
  assert(seen1.length === 0, 'control frames must never be echoed');
  console.log('✅ Control frames (0x00–0x0F) terminate at the server');

  // 7. Legacy v0 frames are gone: the version byte no longer validates.
  p1.send(Buffer.from([0x02, 0x04, 0x00, 0x01, 0x01]), { binary: true }); // v0 score
  p1.send(Buffer.from([0x03, 0x04, 0x00, 0x01, 0x01]), { binary: true }); // v0 turn
  await sleep(250);

  assert(seen2.length === 0, 'legacy v0 frames must be dropped, not forwarded');
  console.log('✅ Legacy v0 frames dropped (strict v1)');

  // 8. Reserved range 0x30+ is dropped and logged.
  p1.send(controlFrame(0x30, p1Id, [0xff]), { binary: true });
  p1.send(controlFrame(0xff, p1Id, []), { binary: true });
  await sleep(250);

  assert(seen2.length === 0, 'reserved opcodes must be dropped, not forwarded');
  console.log('✅ Reserved opcodes (0x30+) dropped');

  // 9. Crash-proofing: empty, truncated and length-lying frames.
  p1.send(Buffer.alloc(0), { binary: true });
  p1.send(Buffer.from([0x01, 0x01, 0x00]), { binary: true }); // short header
  p1.send(Buffer.from([0x01, 0x01, 0x00, 0x00, 0x04, 0x00]), { binary: true }); // length lie
  p1.send(Buffer.from([0x01, 0x10, 0x00, 0x07, 0x09, 0x00]), { binary: true }); // game length lie
  await sleep(250);

  assert(seen2.length === 0, 'malformed frames must never be forwarded');
  assert(p1.readyState === WebSocket.OPEN, 'server must survive garbage input');
  console.log('✅ Server survived garbage input');

  console.log('\n🎉 ALL TESTS PASSED!');
  process.exit(0);
}

run().catch((err) => {
  console.error(`\n❌ ${err.message}`);
  process.exit(1);
});
