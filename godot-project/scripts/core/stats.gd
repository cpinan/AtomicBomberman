# The original's own statistics file, counter for counter.
#
# ---------------------------------------------------------------------------
# WHERE THIS COMES FROM
# ---------------------------------------------------------------------------
# `MESSAGES.TXT` 900 is the file's title, 905 its two column headings, and
# 910-928 are nineteen counter names — the whole file, described in the string
# table and never drawn on any screen. `BM95.EXE` writes it at 0x40200C, and
# that function is short enough to quote in full:
#
#     for i in 0..99:  total[i] += run[i]           ; 0x46442C += 0x46429C
#     f = fopen(bmstats.dat, "wb")                  ; the pointer pair at
#     if f: fwrite(&total, 0x190, 1, f); fclose(f)  ;   0x45B7B0/0x45B7B4
#     f = fopen(bmstats.txt, "wt")
#     if f:
#         fprintf(f, "%s\n\n", message_of(900))
#         fprintf(f, "%s\n\n", message_of(905))
#         for i in 0..18:
#             sprintf(buf, "%s:", message_of(910 + i))
#             fprintf(f, "%-30s %13u %13u\n", buf, total[i], run[i])
#         fclose(f)
#
# Three things follow from that and are honoured here:
#
#   * The binary file is **100 dwords**, not 19, and holds the TOTALS only.
#     The original's accumulate loop runs 0..99 while its print loop runs
#     0..18, so the file has room for counters that were never named. The
#     same 400 bytes are written here, so a file from either program is the
#     same shape.
#   * "Total" is the accumulated column and "Last Run" is this run's. The
#     accumulate happens at save time, which is why saving twice would count
#     this run twice — the original is called once, at exit, and so is this.
#   * The label gets its colon appended BEFORE the padding, so the colon is
#     inside the 30-character field.
#
# ---------------------------------------------------------------------------
# THE FIVE COUNTERS THAT CANNOT BE COLLECTED
# ---------------------------------------------------------------------------
# They are written as 0 rather than dropped, because the file's shape is the
# original's and a missing row would make the two files harder to compare, not
# easier:
#
#   913 Graphic Requests Serviced   the original counts DirectDraw blit
#                                   requests; this port draws through Godot's
#                                   canvas, where the per-frame draw count is
#                                   the renderer's business and not the game's
#   925 Attract Modes Started       there is no attract mode
#   926 Network Packet Retransmits  the netcode is WebSocket over TCP, which
#   927 Ghost Bomb Actions Found    retransmits below the application, and is
#   928 Ghost Bomb Actions Lost     server-authoritative, so it has no ghost
#                                   bombs to reconcile
#
# `docs/AUDIT.md` carries the same list.
extends RefCounted

const Messages_ := preload("res://scripts/core/messages.gd")

## The nineteen, in the order MESSAGES.TXT names them, which is also the order
## they sit in the file.
enum C {
	MATCHES_STARTED = 0,   # 910
	GAMES_STARTED = 1,     # 911 — a "game" is one round
	FRAMES_RENDERED = 2,   # 912
	GRAPHIC_REQUESTS = 3,  # 913 — not collected, see above
	BOMBS_DROPPED = 4,     # 914
	DEATHS_ALL = 5,        # 915
	DEATHS_AI = 6,         # 916
	BRICKS_DESTROYED = 7,  # 917
	PIXELS_RUN = 8,        # 918
	NET_HOSTED = 9,        # 919
	NET_JOINED = 10,       # 920
	BYTES_IN = 11,         # 921
	BYTES_OUT = 12,        # 922
	PACKETS_IN = 13,       # 923
	PACKETS_OUT = 14,      # 924
	ATTRACT_MODES = 15,    # 925 — not collected
	RETRANSMITS = 16,      # 926 — not collected
	GHOST_FOUND = 17,      # 927 — not collected
	GHOST_LOST = 18,       # 928 — not collected
}

## How many are named and printed.
const COUNT := 19

## How many the binary file holds. The original's own accumulate loop bound.
const SLOTS := 100

## Bytes in bmstats.dat: 100 dwords. The original passes 0x190 to fwrite.
const DAT_BYTES := SLOTS * 4

const DAT_PATH := "user://bmstats.dat"
const TXT_PATH := "user://bmstats.txt"

## The first counter's message id. The original indexes 0x38E + i.
const FIRST_ID := 910

## This run, and everything before it. Both are SLOTS long.
var run: PackedInt64Array = PackedInt64Array()
var total: PackedInt64Array = PackedInt64Array()

## Distance is measured in centipixels by the simulation and reported in whole
## pixels by the file, so the remainder is carried rather than truncated once
## per tick — a player walking at 250 cp/tick would otherwise report 2 pixels a
## tick instead of 2.5.
var _distance_cp: int = 0

## Saving accumulates, so it happens once. A second call is a no-op and says so
## to the caller rather than silently doubling the totals.
var _saved: bool = false


func _init() -> void:
	run.resize(SLOTS)
	total.resize(SLOTS)


## Add to one counter. Out-of-range indexes are ignored rather than trapped:
## the counters are telemetry, and a wrong index must not be able to take a
## game down.
func bump(which: int, by: int = 1) -> void:
	if which < 0 or which >= SLOTS:
		return
	run[which] += by


## Movement, in the simulation's own unit. Whole pixels land in the counter and
## the remainder stays here.
func add_distance_cp(centipixels: int) -> void:
	if centipixels <= 0:
		return
	_distance_cp += centipixels
	var whole := _distance_cp / 100
	if whole > 0:
		_distance_cp -= whole * 100
		run[C.PIXELS_RUN] += whole


func value(which: int) -> int:
	if which < 0 or which >= SLOTS:
		return 0
	return run[which]


func total_value(which: int) -> int:
	if which < 0 or which >= SLOTS:
		return 0
	return total[which]


## Read the totals a previous run left. A missing or short file is not an
## error — the first run of the game has neither.
func load_totals(path: String = DAT_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var raw := f.get_buffer(DAT_BYTES)
	f.close()
	if raw.size() < DAT_BYTES:
		return false
	for i in SLOTS:
		total[i] = raw.decode_u32(i * 4)
	return true


## Accumulate this run into the totals and write both files. Returns false if
## it has already been called, or if neither file could be opened.
func save(dat_path: String = DAT_PATH, txt_path: String = TXT_PATH) -> bool:
	if _saved:
		return false
	_saved = true
	for i in SLOTS:
		total[i] += run[i]

	var wrote := false
	var f := FileAccess.open(dat_path, FileAccess.WRITE)
	if f != null:
		var raw := PackedByteArray()
		raw.resize(DAT_BYTES)
		for i in SLOTS:
			# The original's file is unsigned 32-bit. A counter that ran past
			# that wraps there and wraps here.
			raw.encode_u32(i * 4, total[i] & 0xFFFFFFFF)
		f.store_buffer(raw)
		f.close()
		wrote = true

	f = FileAccess.open(txt_path, FileAccess.WRITE)
	if f != null:
		f.store_string(text())
		f.close()
		wrote = true
	return wrote


## The readable file, byte for byte as `0x40200C` formats it.
func text() -> String:
	var out := "%s\n\n" % Messages_.M[900]
	out += "%s\n\n" % Messages_.M[905]
	for i in COUNT:
		out += "%-30s %13d %13d\n" % [
			"%s:" % Messages_.STAT_LABELS[i],
			total[i] & 0xFFFFFFFF,
			run[i] & 0xFFFFFFFF,
		]
	return out
