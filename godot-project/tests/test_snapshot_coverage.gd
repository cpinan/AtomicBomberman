# EVERY FIELD THE VIEW READS MUST CROSS THE WIRE.
#
# A joined client never ticks a simulation; it draws whatever the snapshot
# says. So a Player_ or Bomb_ field that game_view.gd reads but snapshot.gd
# does not carry is drawn from its default on every client, forever — and
# nothing else notices, because the server and every client still agree on
# state_hash(). That has happened three times: the four animation timers
# (60d6b0a), then death_tick and fly_height, found by this suite on its first
# run — deaths still did not animate over the network and punched bombs slid
# along the ground.
#
# docs/IMPROVEMENTS.md C2: rather than find the next one by hand, change each
# field on a server, send a real snapshot, and check what arrives — then fail
# for every field that did not arrive AND that game_view.gd mentions.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Snapshot_ := preload("res://scripts/net/snapshot.gd")

## Fields the view reads that a client legitimately derives for itself. Each
## needs a reason; none do today.
const CLIENT_SIDE := {}


func _init() -> void:
	var t := T_.new("snapshot_coverage")
	var view := FileAccess.get_file_as_string("res://scripts/render/game_view.gd")
	t.ok(not view.is_empty(), "game_view.gd was read")
	for kind in ["player", "bomb"]:
		var carried := _carried(t, kind)
		t.ok(carried.size() > 10, "%d %s fields were tried" % [carried.size(), kind])
		var not_carried := []
		for name in carried:
			if bool(carried[name]):
				continue
			not_carried.append(name)
			if CLIENT_SIDE.has(name):
				continue
			var reads := RegEx.create_from_string("\\.%s\\b" % name)
			t.ok(reads.search(view) == null,
				"[invariant] %s.%s is read by game_view.gd, so a snapshot must carry it"
					% [kind, name])
		t.note("%s fields no snapshot carries (none drawn): %s" % [kind, not_carried])
	quit(t.finish())


func _fixture() -> Sim_:
	var lines := PackedStringArray(["-V,2", "-N,coverage", "-B,0"])
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ".".repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, 1 + p, 1 + (p % 8), p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var scheme := Scheme_.new()
	scheme.parse_text("\n".join(lines), "coverage")
	var sim := Sim_.new()
	sim.setup(scheme, [{"slot": 0, "team": 0}, {"slot": 1, "team": 1}], 7)
	sim.place_bomb(sim.players[0])
	return sim


static func _entity(sim: Sim_, kind: String) -> Object:
	if kind == "player":
		return sim.players[0]
	return sim.bombs[0] if not sim.bombs.is_empty() else null


## name -> true if a changed value survived write() and apply().
func _carried(t: T_, kind: String) -> Dictionary:
	var out := {}
	var probe := _entity(_fixture(), kind)
	if not t.ok(probe != null, "the fixture has a %s" % kind):
		return out
	for prop in probe.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name: String = prop["name"]
		var src := _fixture()
		var changed = _bump(_entity(src, kind).get(name))
		if changed == null:
			t.note("%s.%s: a type this suite cannot change, skipped" % [kind, name])
			continue
		_entity(src, kind).set(name, changed)
		var dst := _fixture()
		Snapshot_.apply(dst, Snapshot_.write(src))
		var arrived := _entity(dst, kind)
		out[name] = arrived != null and arrived.get(name) == changed
	return out


## A different value of the same type, small enough for a byte field.
static func _bump(v: Variant) -> Variant:
	match typeof(v):
		TYPE_BOOL:
			return not v
		TYPE_INT:
			return v + 1 if v < 100 else v - 1
		TYPE_FLOAT:
			return v + 1.0
		TYPE_VECTOR2I:
			return v + Vector2i(1, 1)
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_BYTE_ARRAY:
			var c = v.duplicate()
			if c.size() > 0:
				c[0] = c[0] + 1
			return c
		TYPE_ARRAY:
			var a: Array = v.duplicate()
			if a.size() > 0 and typeof(a[0]) == TYPE_INT:
				a[0] += 1
			else:
				a.append(1)
			return a
	return null
