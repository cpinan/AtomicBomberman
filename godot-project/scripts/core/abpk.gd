# Reader for the ABPK container that tools/abpk.py writes.
#
# Two packs use it — the art pack and the sound pack — so the reader lives here
# rather than inside either of them. One format, one reader, no drift.
#
# WHY A CONTAINER AT ALL. Godot's importer claims any `.png` under res://,
# converts it to its own compressed texture and STRIPS the source from an
# export, so the first web build shipped 58 file names and none of the bytes.
# A `.gdignore` stops the importer but also hides the files from
# `include_filter`, so neither half works alone. One file with an extension
# Godot does not know sidesteps both, arrives byte-for-byte — which the
# recolour shader needs, since it tests pixels for exact green dominance — and
# costs a browser one request instead of hundreds.
#
# Layout, little-endian:
#
#     "ABPK"  4 bytes
#     u32     format version
#     u32     manifest length
#     ...     manifest JSON, UTF-8, whose "blobs" key is name -> [offset, len]
#     ...     the blobs, concatenated
extends RefCounted

const VERSION := 1

var manifest: Dictionary = {}
var error: String = ""

var _bytes := PackedByteArray()
var _index: Dictionary = {}
var _base: int = 0


## Read a container. Returns false and sets `error` if the file is not one;
## never raises, because a truncated pack must fail with a sentence rather than
## take the game down.
func open(path: String) -> bool:
	manifest = {}
	error = ""
	_bytes = PackedByteArray()
	_index = {}
	_base = 0

	if not FileAccess.file_exists(path):
		error = "%s does not exist" % path
		return false
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 12:
		error = "%s is too short to be a container" % path
		return false
	if bytes.slice(0, 4).get_string_from_ascii() != "ABPK":
		error = "%s is not an ABPK container" % path
		return false
	var version := _u32(bytes, 4)
	if version != VERSION:
		error = "%s is container version %d, this build reads %d" \
			% [path, version, VERSION]
		return false
	var manifest_len := _u32(bytes, 8)
	if 12 + manifest_len > bytes.size():
		error = "%s claims a %d-byte manifest and is only %d bytes" \
			% [path, manifest_len, bytes.size()]
		return false
	var parsed: Variant = JSON.parse_string(
		bytes.slice(12, 12 + manifest_len).get_string_from_utf8())
	if not (parsed is Dictionary):
		error = "%s has a manifest that is not a JSON object" % path
		return false

	_bytes = bytes
	_base = 12 + manifest_len
	manifest = parsed
	_index = manifest.get("blobs", {})
	return true


func has(name: String) -> bool:
	return _index.has(name)


func names() -> Array:
	return _index.keys()


## One blob's bytes, or an empty array if it is absent or runs past the end.
func blob(name: String) -> PackedByteArray:
	if not _index.has(name):
		return PackedByteArray()
	var span: Array = _index[name]
	var from: int = _base + int(span[0])
	var to: int = from + int(span[1])
	if to > _bytes.size():
		return PackedByteArray()
	return _bytes.slice(from, to)


static func _u32(b: PackedByteArray, at: int) -> int:
	return b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)
