# Hosting a game

```bash
tools/build_server.sh          # the dedicated server binary
tools/build_web.sh             # the browser client
cd server && docker compose up
```

Then open `http://<your-host>:8080/?join=ws://<your-host>:47600`.

## First time: step by step

Two things have to be running — something serving the page, and something to
play against — and the URL is what connects them. The `?join=` part is not
optional: without it the page loads a menu and has no server to talk to.

**1. Build both halves.** From the repository root, with your copy of the game
in `original-game/`:

```bash
tools/build_server.sh
tools/build_web.sh
```

`build_web.sh` regenerates the asset packs first, so this is also what picks up
new art or sound. It prints the URL to use at the end.

**2. Start them.**

```bash
cd server && docker compose up
```

Two services come up: `web` on port 8080 serving the exported client, and
`game` on 47600 running the simulation. Leave it in the foreground the first
time — the server logs every join, every round and every pause, and that log is
the fastest way to tell what is happening.

**3. Check the server is actually reachable**, before involving a browser at
all:

```bash
tools/ws_probe.py
```

It should print `PROBE OK` after 40 snapshots. If it does, the server is
healthy and anything that goes wrong next is the page or the network — which is
the distinction that is hardest to make from inside a browser.

**4. Open the page.** On the same machine:

    http://localhost:8080/?join=ws://localhost:47600

From another machine on the network, use the host's address in **both** places:

    http://192.168.1.20:8080/?join=ws://192.168.1.20:47600

The second one is the one people get wrong. `ws://localhost` inside the query
string means "the machine the browser is on", so a guest pointing at your page
with `localhost` in the `join=` will try to connect to themselves.

**5. Play.** Arrow keys move, Return drops a bomb. The first click or keypress
is also what starts the audio — see below.

**6. A second player** opens the same URL, in another browser, another window,
or another machine. The server assigns the next free slot and the log says so.

The compose file starts **four bots** (`AB_BOTS`), so the first person to join
has something to play against rather than standing alone on an empty field
waiting for the clock. A bot gives up its seat the moment a human joins, so
those four seats are not lost — set `AB_BOTS: 0` for a humans-only server, and
`AB_WINS` to override the two wins a match takes.

**What "it works" looks like:** the field draws with the original's art, your
bomberman moves, the score line reads `round 1  to 2`, and the server log shows
`<name> joined as slot 0`. If you see the field but nothing moves, the page
loaded and the socket did not — go back to step 3.

## Troubleshooting, in the order worth trying

| symptom | cause |
|---|---|
| page loads, field draws, nothing responds | the WebSocket never connected. Check `?join=` is present and its host is reachable **from the browser**, not from the server. |
| page loads over `https://` and never connects | mixed content — see below. The browser blocks `ws://` from an `https://` page and reports it only in the console. |
| nothing loads at all | the `web` service, or the export. `curl -I http://localhost:8080/index.html` should be `200`. |
| no sound | expected until you click or press a key. See below. |
| everything freezes for everyone | one client is behind or has gone quiet; the server pauses and logs `pause true`. It resumes, or drops that client after 30 s. |
| joined but the game says it is full | ten slots are taken. Bots give up their seats to humans; other humans do not. |

## The mixed-content trap

**A page served over `https://` cannot open a `ws://` socket.** Browsers refuse
it as mixed content, and the failure looks exactly like the server being down —
no error a player would understand, just a client that never joins.

Two ways out:

**Plain HTTP, `ws://`.** What `docker-compose.yml` does. Correct for a LAN, a
VPN, or a tailnet, which is what most self-hosting actually is.

**One origin behind TLS, `wss://`.** Needed for anything on the open internet.
Terminate TLS in front of both services and route by path, so the page and the
socket share an origin:

```
location /            { proxy_pass http://web:80; }
location /play        { proxy_pass http://game:47600;
                        proxy_http_version 1.1;
                        proxy_set_header Upgrade $http_upgrade;
                        proxy_set_header Connection "upgrade"; }
```

Then join with `wss://<your-host>/play`. The `Upgrade` and `Connection` headers
are not optional — without them the proxy answers the WebSocket handshake with
a plain HTTP response and the client reports a protocol error.

## No art or sound ships in the server image

The server draws nothing, plays nothing and needs neither, and the export preset
excludes `data/packs/*`. The **web** build contains both, because a browser
cannot read your disc — which is why a web build is something you make for your
own players from your own copy of the game, not something to publish. See
`docs/PLAN.md` on the two asset packs.

The web `.pck` is about **9.5 MB**: 2.6 MB of art and 7.0 MB of sound. The
sound pack's size comes from VALUELST resource 6, which is the original's own
cache budget, and it can be cut:

```bash
AB_SFX_BUDGET=2000000 tools/build_web.sh     # a 2 MB pack, all 36 events
```

That brings the `.pck` from 9.5 MB to **4.7 MB**. Every event keeps at least
one take at any budget — takes are chosen round-robin — so a smaller pack costs
variety, never silence.

The `.wasm` beside it is 38 MB and compresses to about 10 MB — by far the
largest thing a player downloads. nginx will **not** compress it out of the
box: its default `gzip_types` is `text/html` and nothing else. `server/nginx.conf`
fixes that and `docker-compose.yml` mounts it, so `docker compose up` gets it
right; a hand-rolled host has to do the same.

No `Cross-Origin-Opener-Policy` or `Cross-Origin-Embedder-Policy` headers are
needed, because `export_presets.cfg` has `variant/thread_support=false`. That
is what lets any static file server work. Turn thread support on and both
headers become mandatory or the game refuses to boot.

## No sound until the player clicks

A browser will not start an audio context without a user gesture, so the first
few seconds of a freshly loaded page are silent until something is clicked or
pressed. This is normal and is not the pack failing to load.

## Is my server even reachable?

```bash
tools/ws_probe.py --host <your-host> --port 47600
```

It speaks WebSocket by hand — its own handshake, a browser's `Origin` header,
no Godot involved — joins, and reads snapshots. That separates "the server is
unreachable" from "the page cannot open a socket to it", which the
mixed-content trap above makes very hard to tell apart from inside a browser.

```
handshake: HTTP/1.1 101 Switching Protocols
welcome:   slot 0, seed 1, level 0
scheme:    Just the BASIC SET! (10) (644 B, sent as text so a browser needs no copy of the disc)
match:     round 1, first to 2 wins
snapshots: 40
PROBE OK
```

## What the server does with a slow client

A client more than 16 ticks (800 ms) behind pauses the game for everyone until
it catches up. That is fpc_atomic's rule and its reasoning: the alternative is
letting one player act on a world the others cannot see.

A client silent for 30 seconds loses its seat, which is deliberately generous —
a backgrounded browser tab stops sending and should not be kicked for it. That
silence is measured in **real time**, not in simulation ticks, and the
difference is not academic: counting it in ticks meant a paused server never
counted at all, so one abandoned socket stalled the game permanently.
`docs/BUGS.md` D18.

A tab that is **closed** rather than backgrounded frees its seat at once, from
the socket closing. `docs/BUGS.md` D19.

## Ports

| Port | Service |
|---|---|
| 8080 | the HTML5 client, static files |
| 47600 | the game server, WebSocket |

Change them in `docker-compose.yml`; `AB_PORT` must match the port the client
is told to join.
