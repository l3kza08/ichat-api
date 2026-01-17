Signaling server (Replit deploy)
================================

# Minimal signaling server for iChat

This is a tiny WebSocket-based signaling server to test cross-device P2P for the iChat app.

Features
- Accepts `announce` messages from clients to register users
- Broadcasts `users` list to all connected clients
- Forwards `signal` messages to all other connected clients

Message shapes (JSON):

- Announce (from client when signing in):
```json
{ "type": "announce", "user": { "uid":"user_123", "name":"Alice", "email":"alice@example.com", "photoURL":"" } }
```

- Signal (from client when sending offer/answer/ice or app messages):
```json
{ "type":"signal", "conversationId":"user_123_user_456", "message": { "from":"user_123", "text":"hello" } }
```

- Server broadcasts users:
```json
{ "type":"users", "users": [ {"uid":"user_123","name":"Alice"}, {...} ] }
```

Run locally

```bash
cd tools/signaling
npm install
npm start
```

Notes
- This server is intentionally simple: it broadcasts signals to all other clients. For production use you should route signals only to target peers and secure connections.
- Ensure your clients set the signaling URL in the app (Profile -> Signaling server) to `ws://<host>:8080`.
- If running on the same machine as Android emulators, use `ws://10.0.2.2:8080` for Android emulator (or the host IP for physical devices).
