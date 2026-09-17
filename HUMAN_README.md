# Atomic Bomberman — what this actually is

You remember Atomic Bomberman, the 1997 DOS/Windows game. This project
rebuilds it in a modern engine (Godot 4), and it plays, looks, and sounds
like the real thing — because it's built directly from the original game's
own files, not from memory or from copying someone else's remake.

## Does it work?

Yes. You can start it, play a full match against bots or other people over
the network, blow things up, win or lose, and it uses the original game's
actual artwork, music, sound effects, and 67 official maps.

|  |  |
|---|---|
| ![title screen](docs/screenshots/port-title.png) | ![gameplay](docs/screenshots/port-gameplay-greenacres.png) |

## How was this made?

The original game's install disc has all its pictures, sounds, and maps
stored in old, undocumented file formats. Nobody wrote down how to read
them back in 1997 — so the first job was figuring that out: cracking each
file format, one at a time, and writing a small program for each one that
can pull the real picture, sound, or map out and hand it to the new game
engine.

For a handful of things — exactly how a player moves, how the computer
opponents make decisions, how explosions spread — the disc's data files
don't say. Only the game's actual program (the `.EXE`) knows. So that got
read too, line by line, in a disassembler, until the real logic was
recovered.

Everything is double-checked constantly: there's an automated test suite
with about 6,100 individual checks that runs before any change is trusted,
plus a technique called mutation testing that deliberately breaks the game
in 213 different small ways just to make sure the tests would actually
catch each one if it happened for real (they catch 211 of 213 — the other
two turned out to be impossible to tell apart from the correct version, so
that's fine).

## What was fixed in this latest round of work

A person actually sat down and played it — and found real, live bugs the
automated tests hadn't caught (that keeps happening, on purpose: a computer
checking numbers can't see "does this look right on screen" the way a human
can):

- **Bombs sometimes didn't blow up walls.** Turned out: if a wall was
  hiding a bonus item underneath it (which is how bonus items normally
  work — they're hidden under breakable walls), the explosion would destroy
  the *hidden item* and then stop, leaving the wall standing. About a third
  of the time, across every map in the game. Fixed.
- **The explosion's middle piece didn't quite line up** with the flame
  reaching upward — off by a single pixel, caused by how the game's engine
  rounds fractional pixel positions. Found the exact cause and fixed it.
- **The sound would go completely silent after the first round** of a
  match, because of a bookkeeping mistake in how the game decided whether a
  sound effect was still playing.
- **Picking up and immediately throwing a bomb showed the wrong picture**
  (your character instead of the flying bomb).
- **The computer-controlled bots were missing some tricks** the original
  bots have — like standing on your own bomb and detonating it on purpose —
  and one of their existing tricks (bombing a nearby enemy) worked
  differently than the original game's bots did. Both fixed by re-reading
  exactly what the original program does.

Also added: a built-in **test mode** (press F3 during a game) that lets
anyone place walls, drop any power-up, spawn bombs, or kill/heal a player
on demand — useful for checking that everything still works without having
to hunt for the right map or get lucky with random item drops.

## What's still missing

The biggest one: **the game currently uses the original's own artwork**,
which isn't legally shareable — so before this could ever be a real,
downloadable game, someone needs to draw a whole new set of pictures to
replace it. Everything is already set up to make that swap easy; nobody's
drawn the pictures yet.

A handful of smaller things are also known and written down rather than
forgotten: a couple of keyboard shortcuts from the manual aren't wired up
yet, a few death-animation sound effects couldn't be matched to their
animations, and the computer opponents use a simpler (but still real,
still read from the original) version of their decision-making.

## Where to look next

- `README.md` — the technical version of this document
- `docs/STATUS.md` — what's being worked on right now
- `docs/BUGS.md` — the complete history of everything found and fixed,
  written in plain sentences even though it's a technical document
