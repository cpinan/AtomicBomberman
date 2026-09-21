// Plain-Node test runner for the room directory — no test framework, to match
// server.js's own zero-dependency choice. Run with `npm test` or `node test.js`.
'use strict';

const assert = require('node:assert/strict');
const { server, rooms } = require('./server.js');

let passed = 0;
let failed = 0;

function check(label, fn) {
  try {
    fn();
    passed++;
  } catch (e) {
    failed++;
    console.error(`FAIL ${label}: ${e.message}`);
  }
}

async function main() {
  await new Promise((resolve) => server.listen(0, resolve));
  const port = server.address().port;
  const base = `http://127.0.0.1:${port}`;

  // Health check.
  {
    const res = await fetch(`${base}/health`);
    check('health responds 200', () => assert.equal(res.status, 200));
  }

  // Registering a room returns a well-formed code.
  let code;
  {
    const res = await fetch(`${base}/rooms`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: 'ws://203.0.113.5:47600', name: "Carlos's game" }),
    });
    const body = await res.json();
    check('register responds 200', () => assert.equal(res.status, 200));
    check('register returns a 5-char code', () => assert.match(body.code, /^[A-Z0-9]{5}$/));
    check('code excludes ambiguous characters', () =>
      assert.equal(/[01OI]/.test(body.code), false));
    code = body.code;
  }

  // Looking that code up returns the URL and name.
  {
    const res = await fetch(`${base}/rooms/${code}`);
    const body = await res.json();
    check('lookup responds 200', () => assert.equal(res.status, 200));
    check('lookup returns the registered url', () =>
      assert.equal(body.url, 'ws://203.0.113.5:47600'));
    check('lookup returns the registered name', () =>
      assert.equal(body.name, "Carlos's game"));
  }

  // Lookup is case-insensitive, since a human might type it lowercase.
  {
    const res = await fetch(`${base}/rooms/${code.toLowerCase()}`);
    check('lookup is case-insensitive', () => assert.equal(res.status, 200));
  }

  // An unknown code 404s rather than crashing.
  {
    const res = await fetch(`${base}/rooms/ZZZZZ`);
    check('unknown code responds 404', () => assert.equal(res.status, 404));
  }

  // A heartbeat with the same code updates the SAME room, not a new one.
  {
    const before = rooms.size;
    const res = await fetch(`${base}/rooms`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code, url: 'ws://203.0.113.5:47600', name: "Carlos's game" }),
    });
    const body = await res.json();
    check('heartbeat keeps the same code', () => assert.equal(body.code, code));
    check('heartbeat does not create a second room', () => assert.equal(rooms.size, before));
  }

  // A heartbeat for a code that no longer exists mints a fresh one instead
  // of erroring — a host that missed a window should not get stuck.
  {
    const res = await fetch(`${base}/rooms`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code: 'GONE0', url: 'ws://203.0.113.9:47600', name: 'x' }),
    });
    const body = await res.json();
    check('stale code is replaced, not rejected', () => assert.equal(res.status, 200));
    check('a genuinely new code comes back', () => assert.notEqual(body.code, 'GONE0'));
  }

  // Registering with a non-ws(s) URL is refused — this directory only ever
  // hands the URL back out for a client to dial, never dials it itself, but
  // it should not become a place to stash arbitrary strings.
  {
    const res = await fetch(`${base}/rooms`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url: 'javascript:alert(1)', name: 'x' }),
    });
    check('non-ws url is rejected', () => assert.equal(res.status, 400));
  }

  // Malformed JSON body doesn't crash the process.
  {
    const res = await fetch(`${base}/rooms`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{not json',
    });
    check('malformed body responds 400', () => assert.equal(res.status, 400));
  }

  // The list endpoint includes a registered room.
  {
    const res = await fetch(`${base}/rooms`);
    const body = await res.json();
    check('list includes the registered code', () =>
      assert.ok(body.rooms.some((r) => r.code === code)));
  }

  // Expiry: back-date a room's lastSeen past the TTL directly (the fastest
  // way to test a time-based prune without slowing the suite down or
  // mocking Date globally) and confirm both lookup and listing drop it.
  {
    const staleCode = 'STALE';
    rooms.set(staleCode, { url: 'ws://203.0.113.9:47600', name: 'old', lastSeen: 0 });
    const lookupRes = await fetch(`${base}/rooms/${staleCode}`);
    check('an expired room 404s on lookup', () => assert.equal(lookupRes.status, 404));
    const listRes = await fetch(`${base}/rooms`);
    const listBody = await listRes.json();
    check('an expired room is absent from the list', () =>
      assert.ok(!listBody.rooms.some((r) => r.code === staleCode)));
  }

  server.close();
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

main();
