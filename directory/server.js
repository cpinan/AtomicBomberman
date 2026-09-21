// The room-code lookup directory.
//
// This is NOT a relay: no game byte ever passes through here. A dedicated
// Atomic Bomberman server (scripts/net/server.gd, deployed the way
// server/README.md documents) is already reachable on its own public port —
// the only thing missing was a way to hand someone a short code instead of a
// raw ws://host:port URL. This service is exactly that one job: remember
// which code maps to which URL, and forget it again once the host stops
// saying it's still there.
//
// Zero dependencies on purpose — Node's own `http` module is enough for four
// tiny routes, and a service this small should not need `npm install` to
// audit or to run.
'use strict';

const http = require('http');

const PORT = parseInt(process.env.PORT || '8420', 10);

// A room not re-registered within this long is assumed dead and dropped.
// The Godot client re-registers (heartbeats) well inside this window — see
// scripts/net/directory.gd's HEARTBEAT_SECONDS.
const TTL_MS = 60 * 1000;

// No 0/O/1/I — the whole point of a "room code" is someone reads it aloud or
// types it once, and those four are the ones people misread or mistype.
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 5;

// code -> { url, name, lastSeen }
const rooms = new Map();

function makeCode() {
  let code;
  do {
    code = '';
    for (let i = 0; i < CODE_LENGTH; i++) {
      code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
    }
  } while (rooms.has(code)); // astronomically rare, checked anyway
  return code;
}

function pruneExpired() {
  const cutoff = Date.now() - TTL_MS;
  for (const [code, room] of rooms) {
    if (room.lastSeen < cutoff) rooms.delete(code);
  }
}

function readBody(req, maxBytes, cb) {
  let data = '';
  let tooBig = false;
  req.on('data', (chunk) => {
    data += chunk;
    if (data.length > maxBytes) {
      tooBig = true;
      req.destroy();
    }
  });
  req.on('end', () => {
    if (tooBig) return; // request already destroyed; nothing to respond to
    cb(data);
  });
}

function sendJson(res, status, body) {
  const text = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(text),
  });
  res.end(text);
}

function isValidUrl(url) {
  // The directory only ever hands this back out verbatim for a client to
  // connect to — it never dials it itself — so validation is just "is this a
  // ws(s) URL", not a reachability check.
  return typeof url === 'string' && /^wss?:\/\/.+/.test(url) && url.length <= 256;
}

function isValidName(name) {
  return typeof name === 'string' && name.length <= 64;
}

const server = http.createServer((req, res) => {
  pruneExpired();

  const url = new URL(req.url, `http://${req.headers.host}`);

  if (req.method === 'GET' && url.pathname === '/health') {
    sendJson(res, 200, { ok: true, rooms: rooms.size });
    return;
  }

  if (req.method === 'POST' && url.pathname === '/rooms') {
    readBody(req, 4096, (raw) => {
      let payload;
      try {
        payload = JSON.parse(raw);
      } catch (e) {
        sendJson(res, 400, { error: 'malformed JSON body' });
        return;
      }
      if (!isValidUrl(payload.url)) {
        sendJson(res, 400, { error: 'url must be a ws:// or wss:// address' });
        return;
      }
      const name = isValidName(payload.name) ? payload.name : '';

      // A heartbeat carries the code it was given before; anything else
      // (missing code, or a code that has since expired) mints a new one
      // rather than erroring, so a host that misses one heartbeat window
      // just gets a fresh code instead of being stuck.
      let code = typeof payload.code === 'string' ? payload.code : null;
      if (!code || !rooms.has(code)) {
        code = makeCode();
      }
      rooms.set(code, { url: payload.url, name, lastSeen: Date.now() });
      sendJson(res, 200, { code });
    });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/rooms') {
    const list = [];
    for (const [code, room] of rooms) {
      list.push({ code, name: room.name });
    }
    sendJson(res, 200, { rooms: list });
    return;
  }

  const roomMatch = req.method === 'GET' && url.pathname.match(/^\/rooms\/([A-Za-z0-9]+)$/);
  if (roomMatch) {
    const room = rooms.get(roomMatch[1].toUpperCase());
    if (!room) {
      sendJson(res, 404, { error: 'no such room (expired, or never existed)' });
      return;
    }
    sendJson(res, 200, { url: room.url, name: room.name });
    return;
  }

  sendJson(res, 404, { error: 'not found' });
});

if (require.main === module) {
  server.listen(PORT, () => {
    console.log(`room directory listening on :${PORT}`);
  });
}

module.exports = { server, rooms, TTL_MS, makeCode, isValidUrl, isValidName };
