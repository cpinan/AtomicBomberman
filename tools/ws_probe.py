#!/usr/bin/env python3
"""Check a running game server from outside Godot, with no browser involved.

WHY THIS EXISTS. `tests/test_netplay.gd` already runs a server and two clients
over real WebSockets, but both ends are Godot, so it cannot tell whether the
server would talk to anything else. A browser runs the same GDScript client —
what it changes is the TRANSPORT: its own WebSocket stack, its own handshake,
its own `Origin` header. This speaks that side by hand.

It is also the answer to "is my server actually reachable", which is the first
question a self-hoster has and the one the mixed-content trap makes hardest to
answer (see server/README.md).

    tools/ws_probe.py                       localhost:47600
    tools/ws_probe.py --host box --port 47600

Prints the welcome, the match state and how many snapshots arrived, and exits
non-zero if the server did not behave.

KNOWN LIMITATION, and it is this file's and not the server's. About once per
forty snapshots the reader below produces one short message it cannot classify
— typically four bytes. The server is not sending it: `tests/test_netplay.gd`
compares the client's `state_hash()` to the server's on every snapshot and they
are equal, which is impossible if a snapshot were arriving four bytes short. So
the framing here loses sync once in a while. It is reported rather than hidden,
and it does not affect what the probe is for.
"""

import argparse
import base64
import os
import socket
import struct
import sys

C_HELLO, C_INPUT, C_HEARTBEAT, C_READY = 1, 2, 3, 4
S_WELCOME, S_SNAPSHOT, S_ROUND_OVER = 64, 65, 66
S_SOUNDS, S_REJECT, S_PAUSE, S_MATCH, S_SLOT_OVERRIDDEN = 67, 68, 69, 70, 71
# Must track godot-project/scripts/net/protocol.gd's own Protocol_.VERSION —
# this file speaks the wire format by hand and there is no shared import to
# keep the two in sync. Found stale at 2 (2026-09-18): the real server had
# moved to 4 across two unrelated sessions (hold-to-carry, then the netplay
# override key) and every probe run since had been silently REJECTED on a
# version mismatch, which is a specific enough error that nobody noticed the
# probe itself — not the server — was the stale half.
PROTOCOL_VERSION = 4

NAMES = {
    S_WELCOME: "welcome", S_SNAPSHOT: "snapshot", S_ROUND_OVER: "round over",
    S_SOUNDS: "sounds", S_REJECT: "reject", S_PAUSE: "pause",
    S_MATCH: "match",
}
REJECTS = {1: "protocol version mismatch", 2: "the game is full",
           3: "that name is taken", 4: "the round is already under way"}


class Ws:
    """The smallest WebSocket client that can hold this conversation."""

    def __init__(self, host: str, port: int, origin: str):
        key = base64.b64encode(os.urandom(16)).decode()
        req = (f"GET / HTTP/1.1\r\nHost: {host}:{port}\r\n"
               f"Upgrade: websocket\r\nConnection: Upgrade\r\n"
               f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
               f"Origin: {origin}\r\n\r\n")
        self.sock = socket.create_connection((host, port), timeout=5)
        self.sock.sendall(req.encode())
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(1)
            if not chunk:
                raise ConnectionError("the server closed during the handshake")
            head += chunk
        self.status = head.split(b"\r\n")[0].decode()

    def send(self, payload: bytes) -> None:
        # A client MUST mask; a server must not. Getting this wrong is a
        # protocol violation the peer is entitled to close the socket over.
        mask = os.urandom(4)
        body = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        n = len(payload)
        frame = b"\x82"                       # FIN + binary
        if n < 126:
            frame += bytes([0x80 | n])
        elif n < 65536:
            frame += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            frame += bytes([0x80 | 127]) + struct.pack(">Q", n)
        self.sock.sendall(frame + mask + body)

    def _read(self, n: int) -> bytes:
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise EOFError
            buf += chunk
        return buf

    def recv(self) -> tuple[int, bytes]:
        """(opcode, payload) for one whole MESSAGE, fragments reassembled.

        Reassembly is not optional. A snapshot is about 3 KB and arrives split
        across frames, so a reader that returns each frame as a message hands
        back a truncated snapshot and then reads the tail as if it were a new
        message — which is where the first version of this probe got its
        "message id 176" from, once per run, on a server that was behaving
        perfectly.
        """
        data = b""
        opcode = None
        while True:
            b1, b2 = self._read(2)
            fin = b1 & 0x80
            this = b1 & 0x0F
            n = b2 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._read(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._read(8))[0]
            body = self._read(n)
            if opcode is None:
                opcode = this
            if this in (0x1, 0x2, 0x0):
                data += body
            else:
                # A control frame is never fragmented and never interleaved
                # with a message's data frames.
                return this, body
            if fin:
                return opcode, data


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=47600)
    ap.add_argument("--snapshots", type=int, default=60,
                    help="how many to wait for before declaring success")
    ap.add_argument("--origin", default="http://127.0.0.1:8080",
                    help="the Origin header a browser would send")
    args = ap.parse_args(argv)

    try:
        ws = Ws(args.host, args.port, args.origin)
    except OSError as exc:
        print(f"probe: cannot reach {args.host}:{args.port} — {exc}")
        return 2
    print(f"handshake: {ws.status}")
    if "101" not in ws.status:
        print("probe: the server refused the WebSocket upgrade")
        return 1

    # A unique name per run. A previous probe keeps its seat until it times out
    # and the server refuses a duplicate name — correctly, and confusingly if
    # you do not know that is what happened.
    name = ("probe-" + base64.b32encode(os.urandom(5)).decode().lower()).encode()
    ws.send(bytes([C_HELLO]) + struct.pack("<H", PROTOCOL_VERSION)
            + struct.pack("<H", len(name)) + name)

    seen: dict[int, int] = {}
    snapshots = 0
    other_frames = 0
    ready = False
    welcomed = False
    matched = False
    for _ in range(args.snapshots * 8):
        try:
            opcode, msg = ws.recv()
        except (EOFError, OSError):
            break
        if opcode != 0x2 or not msg:
            other_frames += 1
            continue
        seen[msg[0]] = seen.get(msg[0], 0) + 1
        if msg[0] not in NAMES:
            # This probe's framing, not the server's stream — see the module
            # docstring. Printed so it is never mistaken for a protocol bug.
            print(f"  [probe lost sync: id {msg[0]}, {len(msg)} B, "
                  f"{msg[:10].hex(' ')}]")

        if msg[0] == S_REJECT:
            print(f"probe: REFUSED — {REJECTS.get(msg[1], msg[1])}")
            return 1
        if msg[0] == S_WELCOME:
            welcomed = True
            slot, level = msg[1], msg[6]
            round_seed = struct.unpack("<I", msg[2:6])[0]
            length = struct.unpack("<H", msg[8:10])[0]
            scheme = msg[10:10 + length].decode("utf-8", "replace")
            title = next((l[3:] for l in scheme.splitlines()
                          if l.startswith("-N,")), "?")
            print(f"welcome:   slot {slot}, seed {round_seed}, level {level}")
            print(f"scheme:    {title} ({length} B, sent as text so a browser "
                  f"needs no copy of the disc)")
        elif msg[0] == S_MATCH:
            matched = True
            print(f"match:     round {msg[1] + 1}, first to {msg[7]} wins")
        elif msg[0] == S_SNAPSHOT:
            snapshots += 1
            if not ready:
                ws.send(bytes([C_READY]))
                ready = True
            # Report the tick back, or the server pauses everyone once we are
            # 16 ticks behind — which is correct of it, and would make this
            # probe measure the pause instead of the game.
            ws.send(bytes([C_HEARTBEAT]) + msg[1:5])
        if snapshots >= args.snapshots:
            break

    print(f"snapshots: {snapshots}")
    print("messages:  " + ", ".join(
        f"{NAMES.get(k, 'unparsed ' + str(k))} x{v}"
        for k, v in sorted(seen.items())))
    if other_frames:
        # Pings, pongs and the close frame. Counted rather than ignored so a
        # number here is never mistaken for a lost game message.
        print(f"           ({other_frames} non-binary WebSocket frames)")

    ok = welcomed and matched and snapshots >= args.snapshots
    print("PROBE " + ("OK" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
