Signaling server (Replit deploy)
================================

คำอธิบายสั้น ๆ
---
โฟลเดอร์นี้มี signaling server แบบง่าย (HTTP + WebSocket) ที่ใช้สำหรับการทดสอบ P2P ของโปรเจค iChat.
ไฟล์สำคัญ:

- `server.js` : HTTP server ที่ให้ `/status` และ `/ice` endpoint และเป็น WebSocket server ด้วย
- `package.json` : สคริปต์สำหรับรัน
- `public/index.html` : หน้า status แบบเรียบง่าย (สามารถ deploy แยกเป็น static site ได้)

Deploy บน Replit (สรุป)
---
1. สร้าง Replit ใหม่ → เลือกเทมเพลต **Node.js**
2. อัพโหลดไฟล์จากโฟลเดอร์ `tools/signaling` (หรือเชื่อม repo แล้วเลือกโฟลเดอร์นี้เป็นโปรเจค)
3. ใน Replit UI → Secrets (Environment variables) ให้เพิ่มตัวแปรต่อไปนี้ (ตัวอย่าง):
  - `ICE_SERVERS_JSON` : ใส่เป็น JSON string ของ `iceServers` (ตัวอย่างด้านล่าง)
  - `ICE_REVEAL_TOKEN` : (optional) secret token used to reveal full ICE credentials via `Authorization: Bearer <token>` when visiting the status page.
   - ตัวอย่าง: `[{"urls":"stun:stun.l.google.com:19302"},{"urls":"turn:turn.example.org","username":"turnuser","credential":"turnpass"}]`
     - หมายเหตุ: พาสเวิร์ด/credential ควรเก็บเป็น secret ใน Replit ไม่ควร commit ลง git
4. ตั้งค่า Run command เป็น:

```
node server.js
```

5. กด Run — Replit จะเริ่ม server และมอบ URL สาธารณะให้ (เช่น `https://my-repl.repl.co`).
   - WebSocket URL สำหรับ client: `wss://<your-repl>.repl.co` (ใช้ `wss` เมื่อเข้าถึงผ่าน HTTPS)
   - HTTP endpoints:
     - `GET /status` — คืนค่าสถานะ server
     - `GET /ice` — คืนค่า `{ "iceServers": [...] }` ตาม env var หรือ default STUN. To reveal full (sensitive) credentials, call with header `Authorization: Bearer <ICE_REVEAL_TOKEN>`.

คำแนะนำเพิ่มเติม
---
- Replit free tier จะทำให้ container หลับเมื่อไม่มีการใช้งาน — ถาต้องการ signaling ที่เชื่อมต่อยาว ๆ ให้เปิด **Always On** (จ่าย)
- ถาต้องการรองรับผู้ใช้จำนวนมากหรือ latency/connection ที่ดีกว่า ให้พิจารณา deploy ที่ Fly.io, Railway, Render หรือ VPS แทน
- ถ้าจะใช้ TURN ให้ตั้ง `ICE_SERVERS_JSON` เป็น JSON ของ array `iceServers` (เช่นเดียวกับที่ WebRTC ต้องการ) และเก็บ username/credential เป็น secret

ตัวอย่าง `ICE_SERVERS_JSON`
```
[ 
  { "urls": "stun:stun.l.google.com:19302" },
  { "urls": "turn:turn.example.org:3478", "username": "turnuser", "credential": "turnpass" }
]
```

ตัวอย่างการทดสอบจากเครื่องของคุณ (หลัง deploy)
```
curl https://<your-repl>.repl.co/status
curl https://<your-repl>.repl.co/ice

# To reveal sensitive ICE configuration (uses Authorization header):
curl -H "Authorization: Bearer <token>" https://<your-repl>.repl.co/ice

# ทดสอบ WebSocket (ตัวอย่างด้วย websocat):
websocat wss://<your-repl>.repl.co
```

ความปลอดภัย / ข้อควรระวัง
---
- อย่าเก็บ TURN credentials ใน repo หรือไฟล์ที่เปิดเผย
- ถ้าต้องการ authentication เพิ่มเติม ให้พิจารณาเพิ่ม token checking ใน `server.js` (เช่น Bearer token ใน header หรือ field ใน `announce` message)

ถ้าต้องการ ผมสามารถ:
- เพิ่มตัวอย่างการตั้งค่า Replit (ภาพหน้าจอ / step-by-step)
- ปรับ `public/index.html` ให้ดึงและแสดง `/ice` ด้วย
- เตรียม Dockerfile หรือ template สำหรับ Fly/Railway
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
