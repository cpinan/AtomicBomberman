# Where the user's copy of the original game lives.
#
# The CD's DATA tree is not part of the project: it is copyrighted, gitignored,
# and belongs to whoever owns the disc. So the suites read it from the real
# filesystem rather than from res://, and this is the one place that decides
# where.
#
# Resolution order:
#   1. $AB_DATA, so CI or a differently-laid-out machine can point elsewhere
#   2. <project>/../original-game, the layout docs/PLAN.md describes
class_name DataPath


static func root() -> String:
	var env := OS.get_environment("AB_DATA")
	if not env.is_empty():
		return env.rstrip("/")
	return ProjectSettings.globalize_path("res://").path_join("../original-game") \
		.simplify_path()


static func available() -> bool:
	return DirAccess.dir_exists_absolute(root().path_join("RES"))


## A suite that needs the original's data and cannot find it should say so
## clearly and skip, not fail: a missing disc is not a broken port. It must
## still print its own Result: line, which the caller does.
static func explain_missing() -> String:
	return ("original game data not found at %s — set AB_DATA to the CD's "
		+ "DATA folder (see docs/PLAN.md)") % root()


static func schemes() -> String:
	return root().path_join("SCHEMES")


static func res() -> String:
	return root().path_join("RES")
