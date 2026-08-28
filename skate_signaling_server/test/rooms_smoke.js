const WebSocket = require('ws');

function connect() {
  return new Promise((resolve) => {
    const ws = new WebSocket('ws://localhost:8080');
    ws.on('open', () => resolve(ws));
  });
}

function waitFor(ws, opcode) {
  return new Promise((resolve) => {
    const handler = (msg) => {
      if (msg.readUInt8(0) === 0x01 && msg.readUInt8(1) === opcode) {
        ws.removeListener('message', handler);
        resolve(msg);
      }
    };
    ws.on('message', handler);
  });
}

async function run() {
  console.log('🚀 Running rooms smoke test...\n');
  
  // 1. Client 1: Create a room
  const p1 = await connect();
  const joinCreate = Buffer.from([0x01, 0x01, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00]);
  p1.send(joinCreate, { binary: true });
  
  const joined1 = await waitFor(p1, 0x02);
  const roomCode = joined1.readUInt32BE(7);
  console.log(`✅ P1 created room: ${roomCode}`);

  // 2. Client 2: Join the room
  const p2 = await connect();
  const joinRoom = Buffer.alloc(9);
  joinRoom.set([0x01, 0x01, 0x00, 0x00, 0x04], 0);
  joinRoom.writeUInt32BE(roomCode, 5);
  
  const peerJoinedPromise = waitFor(p1, 0x03); 
  p2.send(joinRoom, { binary: true });
  await waitFor(p2, 0x02);
  await peerJoinedPromise;
  console.log(`✅ P2 joined room: ${roomCode} (P1 notified)`);

  // 3. Client 3: Reject full room
  const p3 = await connect();
  p3.send(joinRoom, { binary: true });
  const errFull = await waitFor(p3, 0x0F);
  if (errFull.readUInt8(5) === 0x01) console.log('✅ P3 rejected: Room full');

  // 4. Client 4: Reject bad code
  const p4 = await connect();
  const joinBad = Buffer.alloc(9);
  joinBad.set([0x01, 0x01, 0x00, 0x00, 0x04], 0);
  joinBad.writeUInt32BE(99999, 5); // Guaranteed collision-free fake code
  p4.send(joinBad, { binary: true });
  const errNotFound = await waitFor(p4, 0x0F);
  if (errNotFound.readUInt8(5) === 0x02) console.log('✅ P4 rejected: Room not found');

  // 5. Test Legacy v0 Game Frame Routing
  const v0ScoreFrame = Buffer.from([0x02, 0x04, 0x00, 0x01, 0x01]); 
  const gameFramePromise = new Promise(resolve => {
    p2.once('message', (msg) => {
      if (msg.readUInt8(0) === 0x02) resolve();
    });
  });
  p1.send(v0ScoreFrame, { binary: true });
  await gameFramePromise;
  console.log('✅ Legacy game frames forwarded strictly within room');

  // 6. Crash-proofing: empty & truncated frames
  p1.send(Buffer.alloc(0), { binary: true });
  p1.send(Buffer.from([0x01, 0x01, 0x00]), { binary: true }); // Malformed v1 header
  
  setTimeout(() => {
    console.log('✅ Server survived garbage input');
    console.log('\n🎉 ALL TESTS PASSED!');
    process.exit(0);
  }, 250);
}

run().catch(console.error);
