// Minimal WebSocket signaling server for iChat P2P testing
// Usage:
//   npm install
//   npm start

const WebSocket = require('ws');
const port = process.env.PORT || 8080;
const wss = new WebSocket.Server({ port });

// Map uid -> { ws, info }
const clients = new Map();

function broadcastUsers() {
  const users = [];
  for (const [uid, entry] of clients.entries()) {
    const info = entry.info || {};
    users.push({ uid, ...info });
  }
  const payload = JSON.stringify({ type: 'users', users });
  for (const [uid, entry] of clients.entries()) {
    try { entry.ws.send(payload); } catch (e) { /* ignore */ }
  }
}

wss.on('connection', function connection(ws) {
  ws.isAlive = true;
  ws.on('pong', () => ws.isAlive = true);

  ws.on('message', function incoming(message) {
    let msg = null;
    try { msg = JSON.parse(message.toString()); } catch (e) { return; }
    const type = msg.type || '';

    if (type === 'announce' && msg.user && msg.user.uid) {
      const uid = msg.user.uid;
      clients.set(uid, { ws, info: { name: msg.user.name, email: msg.user.email, photoURL: msg.user.photoURL, username: msg.user.username, status: msg.user.status } });
      // send current users to everyone
      broadcastUsers();
      return;
    }

    if (type === 'signal') {
      // Forward signal to all other clients (simple approach).
      // Clients will only act on signals for conversationIds they care about.
      const payload = JSON.stringify({ type: 'signal', conversationId: msg.conversationId, message: msg.message });
      for (const [uid, entry] of clients.entries()) {
        if (entry.ws !== ws) {
          try { entry.ws.send(payload); } catch (e) { /* ignore */ }
        }
      }
      return;
    }

    // Optional: handle client request to remove/cleanup
    if (type === 'leave' && msg.uid) {
      clients.delete(msg.uid);
      broadcastUsers();
      return;
    }
  });

  ws.on('close', function close() {
    // remove any entries referencing this ws
    for (const [uid, entry] of clients.entries()) {
      if (entry.ws === ws) clients.delete(uid);
    }
    broadcastUsers();
  });

  ws.on('error', () => {});
});

// Simple liveness ping
setInterval(() => {
  for (const [uid, entry] of clients.entries()) {
    const ws = entry.ws;
    if (!ws.isAlive) {
      try { ws.terminate(); } catch (_) {}
      clients.delete(uid);
      broadcastUsers();
    } else {
      ws.isAlive = false;
      try { ws.ping(); } catch (_) {}
    }
  }
}, 30000);

console.log('Signaling server listening on port', port);
