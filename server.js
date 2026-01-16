// Minimal WebSocket signaling server for iChat P2P testing
// Usage:
//   npm install
//   npm start

const http = require('http');
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

const port = process.env.PORT || 8080;

// create an HTTP server to serve a simple status page and /status endpoint
const server = http.createServer((req, res) => {
  // status endpoint
  if (req.url === '/status') {
    const users = [];
    for (const [uid, entry] of clients.entries()) {
      const info = entry.info || {};
      users.push({ uid, ...info });
    }
    const payload = {
      status: 'ok',
      uptime: Math.floor(process.uptime()),
      clients: clients.size,
      users,
    };
    res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
    res.end(JSON.stringify(payload));
    return;
  }

  // ice endpoint: return ICE servers config from env var (JSON) or default
  if (req.url && req.url.startsWith('/ice')) {
    // get Authorization header if present
    const auth = (req.headers && req.headers.authorization) ? req.headers.authorization : null;

    const envVal = process.env.ICE_SERVERS_JSON || process.env.ICE_SERVERS || null;
    let resp = null;
    if (envVal) {
      try {
        resp = JSON.parse(envVal);
      } catch (e) {
        resp = null;
      }
    }
    if (!resp) {
      resp = [ { urls: 'stun:stun.l.google.com:19302' } ];
    }

    function mask(list) {
      if (!Array.isArray(list)) return list;
      return list.map(s => {
        const copy = Object.assign({}, s);
        if ('credential' in copy) copy.credential = '[REDACTED]';
        if ('password' in copy) copy.password = '[REDACTED]';
        if ('username' in copy && typeof copy.username === 'string') {
          const u = copy.username;
          if (u.length <= 2) copy.username = '*'.repeat(u.length);
          else copy.username = u[0] + '***' + u.slice(-1);
        }
        return copy;
      });
    }

    // simple rate-limiting for reveal attempts per IP
    const ip = req.headers['x-forwarded-for'] ? String(req.headers['x-forwarded-for']).split(',')[0].trim() : (req.socket && req.socket.remoteAddress) ? req.socket.remoteAddress : 'unknown';
    if (!global._revealAttempts) global._revealAttempts = new Map();
    const attempts = global._revealAttempts;
    const now = Date.now();
    const windowMs = 60 * 1000; // 1 minute
    const maxAttempts = 10; // max attempts per window
    const entry = attempts.get(ip) || { count: 0, since: now };
    if (now - entry.since > windowMs) {
      entry.count = 0;
      entry.since = now;
    }

    const revealToken = process.env.ICE_REVEAL_TOKEN || null;
    let revealed = false;
    if (auth && revealToken) {
      const parts = auth.split(' ');
      if (parts.length === 2 && parts[0].toLowerCase() === 'bearer') {
        const token = parts[1];
        if (token === revealToken) {
          revealed = true;
        } else {
          // increment attempts
          entry.count += 1;
          attempts.set(ip, entry);
        }
      }
    }

    // if rate limit exceeded, return 429
    if (entry.count > maxAttempts) {
      res.writeHead(429, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
      res.end(JSON.stringify({ error: 'Too many attempts' }));
      return;
    }

    // logging: only log reveal attempts (mask token)
    if (auth) {
      const masked = auth.length > 20 ? auth.slice(0, 8) + '...' + auth.slice(-8) : auth;
      console.log(`[ice] reveal attempt from ${ip} auth=${masked} revealed=${revealed}`);
    }

    if (revealed) {
      res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
      res.end(JSON.stringify({ iceServers: resp, revealed: true }));
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
    res.end(JSON.stringify({ iceServers: mask(resp), revealed: false }));
    return;
  }

  // serve static files from ./public if present
  let filePath = path.join(__dirname, 'public', req.url === '/' ? 'index.html' : req.url);
  if (!filePath.startsWith(path.join(__dirname, 'public'))) {
    // disallow directory traversal
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }
  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }
    const stream = fs.createReadStream(filePath);
    const ext = path.extname(filePath).toLowerCase();
    const mime = ext === '.html' ? 'text/html' : ext === '.js' ? 'application/javascript' : ext === '.css' ? 'text/css' : 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': mime });
    stream.pipe(res);
  });
});

const wss = new WebSocket.Server({ server });

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

wss.on('connection', function connection(ws, req) {
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

    if (type === 'signal' || type === 'offer' || type === 'answer' || type === 'ice') {
      // If a target is provided, forward only to that client.
      const from = msg.from || null;
      const target = msg.target || null;
      const payload = JSON.stringify(Object.assign({ from }, msg));

      if (target) {
        const entry = clients.get(target);
        if (entry && entry.ws && entry.ws !== ws) {
          try { entry.ws.send(payload); } catch (e) { /* ignore */ }
        }
      } else {
        // Broadcast to all other clients
        for (const [uid, entry] of clients.entries()) {
          if (entry.ws !== ws) {
            try { entry.ws.send(payload); } catch (e) { /* ignore */ }
          }
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

server.listen(port, () => {
  console.log('Signaling server (HTTP+WS) listening on port', port);
});

