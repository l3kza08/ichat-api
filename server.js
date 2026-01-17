// Minimal WebSocket signaling server for iChat P2P testing
// Usage:
//   npm install
//   npm start

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

const port = process.env.PORT || 8080;

// Helper: if SSL cert/key paths are provided via env, try to start HTTPS/WSS
const sslKeyPath = process.env.SSL_KEY_PATH || null;
const sslCertPath = process.env.SSL_CERT_PATH || null;

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

// create an HTTP or HTTPS server to serve a simple status page and /status endpoint
let server;
if (sslKeyPath && sslCertPath && fs.existsSync(sslKeyPath) && fs.existsSync(sslCertPath)) {
  try {
    const key = fs.readFileSync(sslKeyPath);
    const cert = fs.readFileSync(sslCertPath);
    server = https.createServer({ key, cert }, (req, res) => handleRequest(req, res));
    console.log('SSL key/cert found; starting HTTPS + WSS server');
  } catch (e) {
    console.error('Failed to read SSL key/cert, falling back to HTTP:', e.message);
    server = http.createServer((req, res) => handleRequest(req, res));
  }
} else {
  server = http.createServer((req, res) => handleRequest(req, res));
}

// request handler extracted for reuse between http/https
function handleRequest(req, res) {
  // helper: security headers + json responder
  const securityHeaders = {
    'Content-Security-Policy': "default-src 'none'; style-src 'self' 'unsafe-inline' data:; img-src 'self' data:; script-src 'self' 'unsafe-inline'; connect-src 'self' wss: https:; frame-ancestors 'none'; base-uri 'self'",
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'no-referrer',
  };

  function writeJSON(statusCode, obj, extraHeaders) {
    const headers = Object.assign({ 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }, securityHeaders, extraHeaders || {});
    res.writeHead(statusCode, headers);
    res.end(JSON.stringify(obj));
  }

  // status endpoint (masked)
  if (req.url === '/status') {
    // check for reveal token in Authorization header (reuse ICE_REVEAL_TOKEN if USERS_REVEAL_TOKEN not set)
    const auth = (req.headers && req.headers.authorization) ? req.headers.authorization : null;
    const usersRevealToken = process.env.USERS_REVEAL_TOKEN || process.env.ICE_REVEAL_TOKEN || null;
    let usersRevealed = false;
    // simple rate-limiting for reveal attempts per IP (reuse _revealAttempts map)
    const ip = req.headers['x-forwarded-for'] ? String(req.headers['x-forwarded-for']).split(',')[0].trim() : (req.socket && req.socket.remoteAddress) ? req.socket.remoteAddress : 'unknown';
    if (!global._revealAttempts) global._revealAttempts = new Map();
    const attempts = global._revealAttempts;
    const now = Date.now();
    const windowMs = 60 * 1000; // 1 minute
    const maxAttempts = 15; // slightly higher for status
    const entry = attempts.get(ip) || { count: 0, since: now };
    if (now - entry.since > windowMs) {
      entry.count = 0;
      entry.since = now;
    }
    if (auth && usersRevealToken) {
      const parts = auth.split(' ');
      if (parts.length === 2 && parts[0].toLowerCase() === 'bearer') {
        const token = parts[1];
        if (token === usersRevealToken) {
          usersRevealed = true;
        } else {
          entry.count += 1;
          attempts.set(ip, entry);
        }
      }
    }
    if (entry.count > maxAttempts) {
      writeJSON(429, { error: 'Too many attempts' });
      return;
    }
    // mask helper
    function maskEmail(e) {
      if (!e || typeof e !== 'string') return undefined;
      const parts = e.split('@');
      if (parts.length !== 2) return '[REDACTED]';
      const local = parts[0];
      const domain = parts[1];
      if (local.length <= 1) return '*@' + domain;
      return local[0] + '***' + local.slice(-1) + '@' + domain;
    }

    function maskUsername(u) {
      if (!u || typeof u !== 'string') return undefined;
      if (u.length <= 2) return '*'.repeat(u.length);
      return u[0] + '***' + u.slice(-1);
    }

    const shownUsers = [];

    // include persisted users (offline unless online)
    for (const [uid, info] of persistedUsers.entries()) {
      shownUsers.push({
        uid,
        name: info.name || undefined,
        email: usersRevealed ? (info.email || undefined) : maskEmail(info.email),
        username: usersRevealed ? (info.username || undefined) : maskUsername(info.username),
        status: info.statusType || 'offline', // Use stored statusType
      });
    }

    // override/add online users from clients map
    for (const [uid, entry] of clients.entries()) {
      const info = entry.info || {};
      const merged = Object.assign({ uid }, {
        name: info.name || undefined,
        email: usersRevealed ? (info.email || undefined) : maskEmail(info.email || (info.email === undefined ? undefined : info.email)),
        username: usersRevealed ? (info.username || undefined) : maskUsername(info.username),
        status: info.statusType || 'online', // Use statusType from online user, default to 'online'
      });
      // replace any existing entry for uid
      const idx = shownUsers.findIndex(u => u.uid === uid);
      if (idx >= 0) shownUsers[idx] = merged; else shownUsers.push(merged);
    }

    const payload = {
      status: 'ok',
      uptime: Math.floor(process.uptime()),
      clients: clients.size,
      users: shownUsers,
    };
    writeJSON(200, payload);
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
      writeJSON(200, { iceServers: resp, revealed: true });
      return;
    }

      writeJSON(200, { iceServers: mask(resp), revealed: false });
    return;
  }

  // serve static files from ./public if present
  let filePath = path.join(__dirname, 'public', req.url === '/' ? 'index.html' : req.url);
  if (!filePath.startsWith(path.join(__dirname, 'public'))) {
    // disallow directory traversal
    const headers = Object.assign({ 'Content-Type': 'text/plain' }, securityHeaders);
    res.writeHead(403, headers);
    res.end('Forbidden');
    return;
  }
  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) {
      const headers = Object.assign({ 'Content-Type': 'text/plain' }, securityHeaders);
      res.writeHead(404, headers);
      res.end('Not found');
      return;
    }
    const stream = fs.createReadStream(filePath);
    const ext = path.extname(filePath).toLowerCase();
    const mime = ext === '.html' ? 'text/html' : ext === '.js' ? 'application/javascript' : ext === '.css' ? 'text/css' : 'application/octet-stream';
    const headers = Object.assign({ 'Content-Type': mime }, securityHeaders);
    res.writeHead(200, headers);
    stream.pipe(res);
  });
}

const wss = new WebSocket.Server({ server });

// Map uid -> { ws, info }
const clients = new Map();

function broadcastUsers() {
  const allUsersMap = new Map();

  // Start with all persisted users, mark them offline by default
  for (const [uid, info] of persistedUsers.entries()) {
    allUsersMap.set(uid, {
      ...info,
      statusType: info.statusType || 'offline', // Use stored statusType
      online: false, // Mark as offline if not currently connected
    });
  }

  // Override/add users who are currently online
  for (const [uid, entry] of clients.entries()) {
    const onlineUserInfo = {
      ...(allUsersMap.get(uid) || {}),
      ...entry.info,
      statusType: entry.info.statusType || 'online', // Use granular statusType from client
      online: true, // Mark as online
    };
    allUsersMap.set(uid, onlineUserInfo);
  }

  const usersArray = Array.from(allUsersMap.entries()).map(([uid, info]) => ({ uid, ...info }));

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
      const requestId = msg.requestId; // Client should provide a requestId for the response
      const userInfoFromMessage = {
        name: msg.user.name,
        email: (msg.user.email || '').toLowerCase(), // Normalize email to lowercase
        photoURL: msg.user.photoPath || msg.user.photoURL,
        username: (msg.user.username || '').toLowerCase(), // Normalize username to lowercase
        statusType: msg.user.statusType || 'online',
        passwordHash: msg.user.passwordHash,
      };

      // --- Server-side Uniqueness Validation ---
      let error = null;

      // Check for duplicate username
      for (const [existingUid, existingUserInfo] of persistedUsers.entries()) {
        if (existingUid !== uid && existingUserInfo.username === userInfoFromMessage.username) {
          error = 'Username already taken.';
          break;
        }
      }

      // Check for duplicate email
      if (!error) {
        for (const [existingUid, existingUserInfo] of persistedUsers.entries()) {
          if (existingUid !== uid && existingUserInfo.email === userInfoFromMessage.email) {
            error = 'Email already registered.';
            break;
          }
        }
      }

      if (error) {
        // Send error response back to the client
        if (requestId) {
          try {
            ws.send(JSON.stringify({
              type: 'announce_response',
              requestId: requestId,
              status: 'error',
              message: error,
            }));
          } catch (e) {
            console.error('Error sending announce_response:', e.message);
          }
        }
        return; // Stop processing if validation fails
      }

      // Merge with existing persisted info
      const existingPersistedInfo = persistedUsers.get(uid) || {};
      const newInfo = { ...existingPersistedInfo, ...userInfoFromMessage };

      // Clean up undefined values from userInfoFromMessage before merging, to avoid overwriting existing data with undefined
      Object.keys(newInfo).forEach(key => newInfo[key] === undefined && delete newInfo[key]);

      clients.set(uid, { ws, info: newInfo }); // Update active client with new merged info
      persistedUsers.set(uid, newInfo); // Update persisted store
      saveUsers(); // Save to file

      // Send success response back to the client
      if (requestId) {
        try {
          ws.send(JSON.stringify({
            type: 'announce_response',
            requestId: requestId,
            status: 'success',
            message: 'User announced successfully.',
          }));
        } catch (e) {
          console.error('Error sending announce_response:', e.message);
        }
      }

      broadcastUsers();
      return;
    } else if (type === 'request_user_profile' && msg.requestId) {
      const requestId = msg.requestId;
      const requestedUid = msg.uid;
      const requestedEmail = (msg.email || '').toLowerCase();
      const requestedPasswordHash = msg.passwordHash;

      let foundUser = null;

      if (requestedUid) {
        // Lookup by UID
        foundUser = persistedUsers.get(requestedUid);
      } else if (requestedEmail && requestedPasswordHash) {
        // Lookup by email and password hash for login
        for (const [uid, userInfo] of persistedUsers.entries()) {
          if (userInfo.email === requestedEmail && userInfo.passwordHash === requestedPasswordHash) {
            foundUser = { uid, ...userInfo };
            break;
          }
        }
      }

      if (foundUser) {
        // Only send public profile info back, do not send passwordHash back
        const publicProfile = {
          uid: foundUser.uid,
          name: foundUser.name,
          username: foundUser.username,
          photoPath: foundUser.photoURL, // Ensure consistency with client's photoPath
          statusType: foundUser.statusType || 'offline',
          email: foundUser.email, // Include email for the client to verify
        };
        try {
          ws.send(JSON.stringify({
            type: 'request_user_profile_response',
            requestId: requestId,
            status: 'success',
            userProfile: publicProfile,
          }));
        } catch (e) {
          console.error('Error sending request_user_profile_response:', e.message);
        }
      } else {
        try {
          ws.send(JSON.stringify({
            type: 'request_user_profile_response',
            requestId: requestId,
            status: 'error',
            message: 'User not found or credentials invalid.',
          }));
        } catch (e) {
          console.error('Error sending request_user_profile_response:', e.message);
        }
      }
      return;
    } else if (type === 'search_users' && msg.requestId && msg.query) {
      const requestId = msg.requestId;
      const query = String(msg.query).toLowerCase();
      const foundUsers = [];

      for (const [uid, userInfo] of persistedUsers.entries()) {
        const userName = String(userInfo.name || '').toLowerCase();
        const userUsername = String(userInfo.username || '').toLowerCase();

        if (userName.includes(query) || userUsername.includes(query)) {
          // Only send public profile info
          foundUsers.push({
            uid: uid,
            name: userInfo.name,
            username: userInfo.username,
            photoPath: userInfo.photoURL,
            statusType: userInfo.status || 'offline', // Use stored status or default
          });
        }
      }

      const responsePayload = {
        type: 'search_users_response',
        requestId: requestId,
        users: foundUsers,
      };
      try {
        ws.send(JSON.stringify(responsePayload));
      } catch (e) {
        console.error('Error sending search_users_response:', e.message);
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
        user.statusType = 'offline';
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
  const addr = server.address();
  const usedPort = addr && addr.port ? addr.port : port;
  const proto = (sslKeyPath && sslCertPath) ? 'HTTPS+WSS' : 'HTTP+WS';
  console.log(`iChat server (${proto}) listening on port ${usedPort}`);
});

