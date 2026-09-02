const { spawn } = require('child_process');
const path = require('path');
const WebSocket = require('ws');

// The suite runs its own relay: grace has to be milliseconds, not minutes, and
// a dedicated port keeps a dev server on 8080 out of the way.
const PORT = Number(process.env.PORT) || 8129;
const GRACE_MS = Number(process.env.GRACE_MS) || 200;
const GRACE_SECONDS = Math.ceil(GRACE_MS / 1000);

function startServer() {
  const child = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], {
    env: { ...process.env, PORT: String(PORT), GRACE_MS: String(GRACE_MS) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  if (process.env.SMOKE_VERBOSE) {
    child.stdout.on('data', (d) => process.stdout.write(`  [server] ${d}`));
  }
  child.stderr.on('data', (d) => process.stderr.write(`  [server] ${d}`));

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('server did not start')), 5000);
    child.stdout.on('data', (chunk) => {
      if (chunk.toString().includes('listening')) {
        clearTimeout(timer);
        resolve(child);
      }
    });
    child.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

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

const opcodesOf = (seen) => seen.map((msg) => msg.readUInt8(1));

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

// Creates a fresh full room and returns both sockets with their ids.
async function makeRoom() {
  const a = await connect();
  a.send(joinFrame(0), { binary: true });
  const joinedA = await waitFor(a, 0x02);
  const code = joinedA.readUInt32BE(7);
  const aId = joinedA.readUInt16BE(5);

  const b = await connect();
  const aPeerJoined = waitFor(a, 0x03);
  b.send(joinFrame(code), { binary: true });
  const joinedB = await waitFor(b, 0x02);
  const bId = joinedB.readUInt16BE(5);
  const bRole = joinedB.readUInt8(11);
  await aPeerJoined;

  return { code, a, aId, b, bId, bRole };
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

  // ---------------------------------------------------------------------------
  // Reconnect grace (PROTOCOL.md §5). GRACE_MS is milliseconds here.
  // ---------------------------------------------------------------------------

  // 10. A dropped socket puts the room in grace: the survivor gets 0x05.
  const roomC = await makeRoom();
  const seenC = recorder(roomC.a);
  const cDisconnected = waitFor(roomC.a, 0x05);
  roomC.b.close();

  const disc = await cDisconnected;
  assert(disc.readUInt8(4) === 0x04, 'PEER_DISCONNECTED payload must be 4 bytes');
  assert(disc.readUInt16BE(5) === roomC.bId, 'PEER_DISCONNECTED must carry the dropped id');
  assert(
    disc.readUInt16BE(7) === GRACE_SECONDS,
    `PEER_DISCONNECTED must announce the grace window (${GRACE_SECONDS} s)`
  );
  console.log(`✅ Drop → PEER_DISCONNECTED (peer ${roomC.bId}, grace ${GRACE_SECONDS}s)`);

  // 11. A game frame sent while the peer slot is vacant is dropped — silently.
  //     The sender IS in a room, so it must NOT get an ERROR back.
  seenC.length = 0;
  roomC.a.send(trickSetFrame(roomC.aId), { binary: true });
  await sleep(100);
  assert(
    !opcodesOf(seenC).includes(0x0f),
    'an in-grace game frame must be dropped, not answered with ERROR'
  );
  assert(seenC.length === 0, 'nothing may come back from an in-grace game frame');
  console.log('✅ In-grace game frame dropped, no ERROR');

  // 12. Rejoining within the window re-seats the ORIGINAL playerId and role,
  //     and both sides get 0x06. PEER_JOINED is never re-sent.
  const p9 = await connect();
  const seen9 = recorder(p9);
  const aReconnected = waitFor(roomC.a, 0x06);
  p9.send(joinFrame(roomC.code), { binary: true });
  const rejoined = await waitFor(p9, 0x02);

  assert(
    rejoined.readUInt16BE(5) === roomC.bId,
    `rejoin must restore playerId ${roomC.bId}, got ${rejoined.readUInt16BE(5)}`
  );
  assert(rejoined.readUInt32BE(7) === roomC.code, 'rejoin must return the same room code');
  assert(
    rejoined.readUInt8(11) === roomC.bRole,
    `rejoin must restore role ${roomC.bRole}, got ${rejoined.readUInt8(11)}`
  );
  console.log(`✅ Rejoin re-seats player ${roomC.bId} as role ${roomC.bRole}`);

  const aSees = await aReconnected;
  assert(aSees.readUInt16BE(5) === roomC.bId, 'survivor 0x06 must carry the returning id');
  await sleep(100);
  const nineSees = opcodesOf(seen9);
  assert(nineSees.includes(0x06), 'rejoiner must receive PEER_RECONNECTED');
  assert(
    seen9.find((msg) => msg.readUInt8(1) === 0x06).readUInt16BE(5) === roomC.aId,
    'rejoiner 0x06 must carry the survivor id'
  );
  assert(!nineSees.includes(0x03), 'PEER_JOINED must never be re-sent on a rejoin');
  assert(!opcodesOf(seenC).includes(0x03), 'the survivor must not see PEER_JOINED either');
  console.log('✅ PEER_RECONNECTED to both; PEER_JOINED never re-sent');

  // 13. The room forwards again once whole.
  seenC.length = 0;
  const resumed = trickSetFrame(roomC.bId);
  p9.send(resumed, { binary: true });
  await sleep(100);
  assert(seenC.length === 1 && seenC[0].equals(resumed), 'forwarding must resume after a rejoin');
  console.log('✅ Game frames flow again after the rejoin');

  // 14. Grace expiry: PEER_LEFT to the survivor and the room is deleted.
  const roomD = await makeRoom();
  const dLeft = waitFor(roomD.a, 0x04);
  roomD.b.close();
  const left = await dLeft;
  assert(left.readUInt16BE(5) === roomD.bId, 'PEER_LEFT must carry the lost id');

  const p10 = await connect();
  p10.send(joinFrame(roomD.code), { binary: true });
  const errGone = await waitFor(p10, 0x0F);
  assert(errGone.readUInt8(5) === 0x02, 'an expired room must be gone (room not found)');
  console.log('✅ Grace expiry → PEER_LEFT + room deleted');

  // 15. The survivor leaving mid-grace deletes the room immediately, and the
  //     pending timer must not fire on the wreckage.
  const roomE = await makeRoom();
  const eDisconnected = waitFor(roomE.a, 0x05);
  roomE.b.close();
  await eDisconnected;
  roomE.a.close();
  await sleep(GRACE_MS * 3);

  const p11 = await connect();
  p11.send(joinFrame(roomE.code), { binary: true });
  const errWreck = await waitFor(p11, 0x0F);
  assert(errWreck.readUInt8(5) === 0x02, 'a room both peers left must be gone');
  assert(p11.readyState === WebSocket.OPEN, 'server must survive a survivor leaving mid-grace');
  console.log('✅ Survivor leaving mid-grace deletes the room, no late timer');

  console.log('\n🎉 ALL TESTS PASSED!');
}

startServer()
  .then(async (server) => {
    try {
      await run();
      server.kill();
      process.exit(0);
    } catch (err) {
      server.kill();
      console.error(`\n❌ ${err.message}`);
      process.exit(1);
    }
  })
  .catch((err) => {
    console.error(`\n❌ ${err.message}`);
    process.exit(1);
  });
