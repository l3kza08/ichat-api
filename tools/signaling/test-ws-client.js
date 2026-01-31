const WebSocket = require('ws');

const url = process.argv[2] || 'wss://ichat-api--wrphl20.replit.app';

function makeId() {
  return 'agent_' + Math.floor(Math.random() * 1000000) + '_' + Date.now();
}

(async () => {
  const uid = makeId();
  console.log('Connecting to', url, 'as', uid);

  const ws = new WebSocket(url, { handshakeTimeout: 10000 });

  ws.on('open', () => {
    console.log('OPEN');
    const announce = { type: 'announce', user: { uid, name: 'Agent Test', username: 'agent' } };
    ws.send(JSON.stringify(announce));
    console.log('Sent announce');
  });

  ws.on('message', (m) => {
    try {
      const parsed = JSON.parse(m.toString());
      console.log('RECV:', JSON.stringify(parsed, null, 2));
    } catch (e) {
      console.log('RECV (raw):', m.toString());
    }
  });

  ws.on('error', (err) => {
    console.error('WS ERROR:', err && err.message ? err.message : err);
  });

  ws.on('close', (code, reason) => {
    console.log('CLOSED', code, reason && reason.toString ? reason.toString() : reason);
    process.exit(0);
  });

  // Close after 8s
  setTimeout(() => {
    try { ws.close(); } catch (e) {}
  }, 8000);
})();
