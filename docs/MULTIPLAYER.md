# Playing with other people

Four ways, easiest first. All of them work on one machine.

> **Flags go after a bare `--`.** Godot keeps the ones before it for itself.
>
> ```bash
> godot --path . -- --serve 47600      # right
> godot --path . --serve 47600         # works, with a warning telling you to fix it
> ```
>
> The second form used to be silently ignored and gave you a plain local game.
> The game now finds its own flags among Godot's and warns. Everything below
> has the `--` in the right place. `godot` here means the Godot 4 binary; on a
> Mac that is usually `/Applications/Godot.app/Contents/MacOS/Godot`.

---

## 0. From the menu — no terminal at all

**To host:** choose **Start Network Game**, set up the match, press `Enter`.
You land in a lobby that shows everything a friend needs:

```
WAITING IN LOBBY

On this network: ws://192.168.1.20:47600
Others choose Join Network Game; this game is listed
Over the internet: forward TCP port 47600 to this machine
```

Read the address out over voice chat. Press `Enter` when everyone is in.

**To join:** choose **Join Network Game**. Games on your network are listed
under the menu — pick one with left/right and press `Enter`. If yours is not
listed, type the host's address in the field below the list (`192.168.1.20`,
or `host:port` if they changed the port) and press `Enter`.

**When the match is won** everyone goes back to the lobby, which says who won.
The host presses `Enter` to play again; nobody has to relaunch.

**What the messages mean:**

| On screen | Meaning |
|---|---|
| *Could not join: nothing answered at ws://…* | Wrong address, the host is not up yet, or a firewall. Over the internet, the host's router must forward the port |
| *Could not join: protocol version mismatch* | The two of you run different builds. Both update |
| *Could not join: the game is full* | Ten players already |
| *Lost the connection to the host* | The host quit, or either of your connections dropped. Join again with the same name mid-match and you get your own seat and score back |
| *Only the host can start this game* | You pressed `Enter` in a lobby you did not open |

Two players with the same name are both let in; the second shows as
`player 2`. Pass `--name` to choose one.

---

## 1. Two players, one keyboard

No networking, nothing to configure.

```bash
cd godot-project
godot --path . -- --players 2
```

| | Move | Drop bomb | Action |
|---|---|---|---|
| **Player 1** | arrow keys | `Space` | `Enter` |
| **Player 2** | `R` `D` `F` `G` | `S` | `A` |

Those are the disc's own defaults, from `INPUT.BM`. `R`/`D`/`F`/`G` is an
inverted T under the left hand: `R` up, `D` and `G` either side, `F` below.

Add bots to fill the field:

```bash
godot --path . -- --players 2 --bots 4
```

Rebind anything you like from the menu — Options, then the keyboard screen.

---

## 2. Two windows on one machine, over the network

This is the real netplay path: a server, and clients talking to it over
WebSocket. Useful for testing, and the same thing that runs over a LAN.

**Terminal 1 — the host.** It runs the server *and* plays:

```bash
cd godot-project
godot --path . -- --serve 47600 --name host --scale 2
```

**Terminal 2 — the other player:**

```bash
cd godot-project
godot --path . -- --join ws://127.0.0.1:47600 --name player2 --scale 2
```

The client lands in a lobby. **The host presses `Enter` or `Space` to start
the match.** Only the host can; the server checks who is asking.

`--scale 2` gives each window 1280×960 so two fit on screen. Without it each
one takes the largest whole multiple that fits, and they land on top of each
other.

### Expect this warning on the second window

```
WARNING: no LAN game list: cannot listen on 47601
```

Harmless. Only one process on a machine can hold the LAN discovery port, so
the second window cannot *browse* for games on the network. Joining by URL,
which is what you just did, is unaffected.

---

## 3. A dedicated server plus two players

Nobody plays on the server; it just runs the match. No window, no artwork
loaded, so it is cheap.

```bash
# Terminal 1
godot --path . -- --dedicated 47600

# Terminal 2
godot --path . -- --join ws://127.0.0.1:47600 --name p1 --scale 2

# Terminal 3
godot --path . -- --join ws://127.0.0.1:47600 --name p2 --scale 2
```

On another machine on the same network, swap `127.0.0.1` for the server's IP:

```bash
godot --path . -- --join ws://192.168.1.20:47600 --name p2
```

For hosting one on the public internet, see `server/README.md` — it has the
Docker and nginx configuration, and the room-code directory service that lets
players find a game without typing an IP.

---

## Useful extras

| Flag | What it does |
|---|---|
| `--bots N` | fill N slots with AI. Host and local only — a joining client cannot add them, because the server owns the roster |
| `--scheme PATH` | play a specific `.SCH` level |
| `--wins N` | how many round wins take the match |
| `--seconds N` | round length |
| `--kill-total` | win on kills rather than rounds |
| `--random-start 0` | keep each player on their scheme's own start cell |
| `--no-music` / `--mute` | quieter testing |
| `--fullscreen` | start filling the screen (`F11` toggles) |

`scripts/app/main.gd`'s header comment is the full list.

---

## If something goes wrong

**The client cannot connect.** The menu says *nothing answered at …*. Check
the host is up first — start it, wait for its lobby, then join. Check the
port matches on both sides.

**`cannot listen on 47601`.** Expected on every window after the first. See
above.

**Tests refuse to run while a game is open.** `tools/verify.sh` and a live
window both want the LAN discovery port, so verify stops at once and names
the process holding it. Close every game window first:

```bash
pkill -f "Godot --path"
tools/verify.sh
```

**Two windows stacked on top of each other.** Pass `--scale 2` (or `1`) to
both; without it each picks the biggest multiple that fits the screen.
