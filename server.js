// Minimal WebSocket signaling server for iChat P2P testing
// Usage:
//   npm install
//   npm start

const http = require('http');
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

const port = process.env.PORT || 8080;

// New global variable for persisted users
const usersFilePath = path.join(__dirname, 'users.json');
let persistedUsers = new Map(); // Map uid -> user_info

// Function to load users from file
function loadUsers() {
  try {
    if (fs.existsSync(usersFilePath)) {
      const data = fs.readFileSync(usersFilePath, 'utf8');
      const parsed = JSON.parse(data);
      persistedUsers = new Map(Object.entries(parsed));
      console.log(`Loaded ${persistedUsers.size} persisted users.`);
    }
  } catch (e) {
    console.error('Error loading persisted users:', e.message);
  }
}

// Function to save users to file
function saveUsers() {
  try {
    fs.writeFileSync(usersFilePath, JSON.stringify(Object.fromEntries(persistedUsers)), 'utf8');
  } catch (e) {
    console.error('Error saving persisted users:', e.message);
  }
}

// Call loadUsers on startup
loadUsers();

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

    // logging: only log reveal attempts (do NOT print token)
    if (auth) {
      // don't print token value; only indicate that auth header was provided
      const prefix = auth.split(' ')[0] || 'auth';
      console.log(`[ice] reveal attempt from ${ip} auth=${prefix} [REDACTED] revealed=${revealed}`);
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
  const allUsersMap = new Map();

  // Start with all persisted users, mark them offline by default
  for (const [uid, info] of persistedUsers.entries()) {
    allUsersMap.set(uid, { ...info, status: info.status || 'offline' });
  }

  // Override/add users who are currently online
  for (const [uid, entry] of clients.entries()) {
    // Take the latest info from the client entry (which was set by announce)
    const onlineUserInfo = { ...(allUsersMap.get(uid) || {}), ...entry.info, status: 'online' };
    allUsersMap.set(uid, onlineUserInfo);
  }

  const usersArray = Array.from(allUsersMap.values());

  const payload = JSON.stringify({ type: 'users', users: usersArray });
  for (const [uid, entry] of clients.entries()) {
    try { entry.ws.send(payload); } catch (e) { /* ignore */ }
  }
  console.log(`Broadcasting ${usersArray.length} users (${clients.size} online).`);
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
      const userInfoFromMessage = {
        name: msg.user.name,
        email: msg.user.email,
        photoURL: msg.user.photoPath || msg.user.photoURL,
        username: msg.user.username,
        status: msg.user.statusType || 'online',
        recoveryPhraseHash: msg.user.recoveryPhraseHash, // Add new field
      };

      // Merge with existing persisted info
      const existingPersistedInfo = persistedUsers.get(uid) || {};
      const newInfo = { ...existingPersistedInfo, ...userInfoFromMessage };

      // Clean up undefined values from userInfoFromMessage before merging, to avoid overwriting existing data with undefined
      Object.keys(newInfo).forEach(key => newInfo[key] === undefined && delete newInfo[key]);

      clients.set(uid, { ws, info: newInfo }); // Update active client with new merged info
      persistedUsers.set(uid, newInfo); // Update persisted store
      saveUsers(); // Save to file

      broadcastUsers();
      return;
    } else if (type === 'request_user_profile' && msg.requestId && msg.recoveryPhraseHash) {
      const requestId = msg.requestId;
      const recoveryPhraseHash = msg.recoveryPhraseHash;

      let foundUser = null;
      for (const [uid, userInfo] of persistedUsers.entries()) {
        if (userInfo.recoveryPhraseHash === recoveryPhraseHash) {
          foundUser = { uid, ...userInfo };
          break;
        }
      }

      const responsePayload = {
        type: 'user_profile_response',
        requestId: requestId,
        user: foundUser, // Will be null if not found
      };
      try {
        ws.send(JSON.stringify(responsePayload));
      } catch (e) {
        console.error('Error sending user_profile_response:', e.message);
      }
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
    let disconnectedUid = null;
    // Remove any entries referencing this ws and find the disconnected UID
    for (const [uid, entry] of clients.entries()) {
      if (entry.ws === ws) {
        disconnectedUid = uid;
        clients.delete(uid);
        break; // Assuming one ws per uid
      }
    }

    if (disconnectedUid && persistedUsers.has(disconnectedUid)) {
      const user = persistedUsers.get(disconnectedUid);
      if (user) {
        user.status = 'offline';
        persistedUsers.set(disconnectedUid, user);
        saveUsers(); // Persist the offline status
      }
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

