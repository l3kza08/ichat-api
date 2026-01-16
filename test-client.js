const WebSocket = require('ws');

const url = process.argv[2] || 'wss://ichat-api--wrphl20.replit.app';

function makeId(prefix) {
  return prefix + '_' + Math.floor(Math.random() * 1000000) + '_' + Date.now();
}

(async () => {
  const uid1 = makeId('clientA');
  const uid2 = makeId('clientB');

  console.log('Connecting to', url);

  const ws1 = new WebSocket(url);
  const ws2 = new WebSocket(url);

  ws1.on('open', () => {
    console.log('ws1 open, announcing', uid1);
    ws1.send(JSON.stringify({ type: 'announce', user: { uid: uid1, name: 'TestA' } }));
  });

  ws2.on('open', () => {
    console.log('ws2 open, announcing', uid2);
    ws2.send(JSON.stringify({ type: 'announce', user: { uid: uid2, name: 'TestB' } }));
  });

  ws1.on('message', (m) => {
    console.log('[ws1 recv] ', m.toString());
  });
  ws2.on('message', (m) => {
    console.log('[ws2 recv] ', m.toString());
  });

  // after both open, send a targeted signal from ws1 to ws2
  function waitForOpen(ws) {
    return new Promise((res) => {
      if (ws.readyState === WebSocket.OPEN) return res();
      ws.on('open', res);
    });
  }

  await waitForOpen(ws1);
  await waitForOpen(ws2);

  console.log('Both connected — sending targeted signal from ws1 -> ws2');
  const payload = {
    type: 'offer',
    from: uid1,
    target: uid2,
    sdp: 'dummy-sdp-for-test-' + Date.now(),
  };
  ws1.send(JSON.stringify(payload));

  // wait and then close
  setTimeout(() => {
    console.log('Closing connections');
    try { ws1.close(); } catch (e) {}
    try { ws2.close(); } catch (e) {}
    process.exit(0);
  }, 5000);
})();
