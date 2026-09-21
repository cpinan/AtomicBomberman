# Room-code directory

A short code instead of a raw `ws://host:port` URL, for a `server/`
dedicated server someone else deployed. This is a **lookup table, not a
relay** — no game byte ever passes through it. The dedicated server
(`server/README.md`) is already reachable on its own public port once
deployed; this service only remembers which code maps to which URL, and
forgets it again once the host stops saying it's still there.

## Run it

```bash
cd directory && docker compose up
```

Or without Docker:

```bash
cd directory && npm start
```

Either way it listens on `:8420` (override with `PORT`). No database, no
config file — everything lives in memory and is meant to.

## The API

Four routes, JSON in and out:

- `POST /rooms` — body `{"url": "ws://1.2.3.4:47600", "name": "optional"}`.
  Returns `{"code": "AB3XQ"}`. Include the code you were given in a later
  call (as `{"code": "AB3XQ", "url": ..., "name": ...}`) to refresh the same
  room instead of minting a new one — this is the heartbeat a host's game
  process sends every ~20 seconds while it's up.
- `GET /rooms/<code>` — `{"url": ..., "name": ...}`, or 404 if the code is
  unknown or has expired. Case-insensitive.
- `GET /rooms` — `{"rooms": [{"code": ..., "name": ...}, ...]}`, every
  currently-live room, for a browsable join list.
- `GET /health` — `{"ok": true, "rooms": <count>}`.

A room not re-registered for 60 seconds is dropped on the next request that
touches the map — there's no held connection to notice a host disconnecting,
so absence of a heartbeat is the only signal. A host that misses a window
gets a fresh code back rather than an error; nothing about this is meant to
feel fragile to a player who just wants to type five characters to their
friend.

## Deploying alongside `server/`

They're independent services with independent lifecycles — one directory
instance serves every host's games, while each `server/` instance is one
match. Run both on the same VPS on different ports, or the directory
somewhere else entirely; either way, a `server/` deployment that wants to be
found by code needs the directory's public URL (see `AB_DIRECTORY_URL` once
`scripts/net/directory.gd` lands — that part of the client wiring is still
ahead in the plan, this service is step 1).

## Testing

```bash
cd directory && npm test
```

Plain Node, no framework — spins the server up on an ephemeral port and
exercises every route directly, including code-collision avoidance, the
heartbeat-keeps-the-same-code path, and TTL expiry.
