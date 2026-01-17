// test-client.js has been removed/replaced. Use standard WebSocket clients or
// tools such as `wscat` / `websocat` to exercise the signaling server over ws/wss.

// Example (wscat):
//   wscat -c ws://localhost:8080

// Example (node):
//   const ws = new (require('ws'))('ws://localhost:8080');
//   ws.on('open', () => ws.send(JSON.stringify({ type: 'announce', user: { uid: 'me', name: 'me' } })))

// Intentionally left minimal for production usage.
