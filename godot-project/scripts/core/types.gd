# Every enum the simulation and the file parsers share.
#
# Where an enum's order is dictated by one of the original's file formats, that
# is called out and the order must not be rearranged — the ordinal IS the data.
class_name Types

## The 13 powerups, in the order the scheme file's -P lines use and the order
## VALUELST's 50..64, 400..412 and 550..564 blocks are indexed by.
## THE ORDER IS THE FILE FORMAT. Do not rearrange.
enum PowerUp {
	BOMB = 0,
	FLAME = 1,
	DISEASE = 2,
	KICK = 3,
	SKATE = 4,
	PUNCH = 5,
	GRAB = 6,
	SPOOGE = 7,
	GOLDFLAME = 8,
	TRIGGER = 9,
	JELLY = 10,
	SUPER_BAD_DISEASE = 11,
	RANDOM = 12,
}

## Names as the original's own scheme files comment them, for display and for
## making test failures legible.
const POWERUP_NAMES := [
	"an extra bomb",
	"longer flame length",
	"a disease",
	"the ability to kick bombs",
	"extra speed",
	"the ability to punch bombs",
	"the ability to grab bombs",
	"the spooger",
	"goldflame",
	"a trigger mechanism",
	"jelly (bouncy) bombs",
	"super bad disease",
	"random",
]

## The twelve diseases, named by the original itself. SOUNDLST.RES groups its
## sound effects one disease per 50 resources from 3000 to 3550 and comments
## each group with its name — "; molasses", "; constipation", "; controls
## reversed". These are those names in resource order, so the ordinal is the
## original's own.
##
## Cross-check: fpc_atomic implements five of the twelve, and every one of them
## lands on a name here — super-slow is MOLASSES, no-bombs is CONSTIPATION,
## ebola is POOPS, inverted-keyboard is CONTROLS_REVERSED, dud-bombs is DUDS.
##
## OPEN: VALUELST has only NINE duration slots (130..138) for these twelve, and
## which name maps to which slot is not established — docs/BUGS.md Q1. It is
## currently unobservable because all nine slots hold 300, so every disease
## lasts the same 15 seconds; it would start to matter the moment one slot is
## re-tuned.
enum Disease {
	MOLASSES = 0,           ## slowed right down
	CRACK = 1,              ## sped right up
	CONSTIPATION = 2,       ## cannot place bombs
	POOPS = 3,              ## places bombs constantly, whether you want to or not
	SHORT_FLAME = 4,        ## flame length cut to the minimum
	CRACK_POOPS = 5,        ## both at once
	SHORT_FUZE = 6,         ## bombs go off almost at once
	SWAP_PLAYERS = 7,       ## swaps places with another player
	CONTROLS_REVERSED = 8,  ## left is right and up is down
	LEPROSY = 9,            ## powerups fall off as you walk
	INVISIBLE = 10,         ## you cannot see yourself
	DUDS = 11,              ## bombs may not go off at all
}

const DISEASE_NAMES := [
	"molasses", "crack", "constipation", "poops", "short flame",
	"crack poops", "short fuze", "swap 2 players", "controls reversed",
	"leprosy", "invisible", "duds",
]

const DISEASE_COUNT := 12

## The resource number of a disease's first sound in SOUNDLST.RES, which is
## also where its name was read from.
static func disease_sound_base(disease: int) -> int:
	return 3000 + disease * 50

## Diseases the SUPER BAD powerup can inflict, as opposed to the ordinary one.
## VALUELST separates the two powerups (11 vs 2) but does not say which
## diseases belong to which pool. These are the ones that end a round rather
## than inconvenience it, which is the reading fpc_atomic also took — its
## dEbola sits behind puSuperBadDisease. docs/BUGS.md Q1.
const SUPER_BAD_DISEASES := [Disease.POOPS, Disease.CRACK_POOPS,
	Disease.SWAP_PLAYERS, Disease.LEPROSY]

## Everything else, which is what the ordinary disease powerup draws from.
const ORDINARY_DISEASES := [Disease.MOLASSES, Disease.CRACK,
	Disease.CONSTIPATION, Disease.SHORT_FLAME, Disease.SHORT_FUZE,
	Disease.CONTROLS_REVERSED, Disease.INVISIBLE, Disease.DUDS]

## What occupies a cell structurally. The scheme file's -R rows use the
## characters '#', ':' and '.' for these three in this order.
enum Brick {
	SOLID = 0,   ## '#' indestructible
	BRICK = 1,   ## ':' destructible
	BLANK = 2,   ## '.' empty
}

const BRICK_CHARS := {"#": Brick.SOLID, ":": Brick.BRICK, ".": Brick.BLANK}

## Which arms of a flame cross occupy a cell. A cell can hold several at once,
## so these are bit flags rather than an enum of states.
enum Flame {
	CROSS = 1,
	UP = 2,
	DOWN = 4,
	LEFT = 8,
	RIGHT = 16,
	END = 32,
}

## Bomb behaviour. VALUELST resource 43 selects the starting type from the
## first three.
enum BombType {
	REGULAR = 0,
	TRIGGER = 1,
	JELLY = 2,
}

enum BombState {
	NORMAL = 0,
	TIME_TRIGGERED = 1,
	DUD = 2,
	WOBBLE = 3,   ## a jelly bomb that has bounced
}

## Four cardinal directions. The EXTRA files spell these N/S/E/W; the parser
## resolves them to these names so nothing downstream deals in letters.
enum Dir {
	NONE = 0,
	UP = 1,
	DOWN = 2,
	LEFT = 3,
	RIGHT = 4,
}

const DIR_NAMES := {
	"up": Dir.UP,
	"down": Dir.DOWN,
	"left": Dir.LEFT,
	"right": Dir.RIGHT,
}

## Pixel delta for one step in a direction. Movement happens in pixels, so a
## direction is a pixel vector, not a tile vector.
const DIR_VEC := {
	Dir.NONE: Vector2i(0, 0),
	Dir.UP: Vector2i(0, -1),
	Dir.DOWN: Vector2i(0, 1),
	Dir.LEFT: Vector2i(-1, 0),
	Dir.RIGHT: Vector2i(1, 0),
}

## What the player is asking for this tick.
enum MoveState { STILL = 0, LEFT = 1, RIGHT = 2, UP = 3, DOWN = 4 }

enum Action { NONE = 0, FIRST = 1, SECOND = 2, FIRST_DOUBLE = 3, SECOND_DOUBLE = 4 }

enum Key { NONE = 0, UP = 1, DOWN = 2, LEFT = 3, RIGHT = 4, FIRST = 5, SECOND = 6 }

## Which animation the client should be showing for a player.
enum Anim {
	STAND = 0,
	WALK = 1,
	KICK = 2,
	PUNCH = 3,
	PICKUP = 4,
	DIE = 5,
	TELEPORT = 6,
	ZEN = 7,
	CORNERED = 8,
}

## Animations the server sends once as an edge and the client then runs to
## completion on its own, rather than being told about every tick.
const ONE_SHOT_ANIMS := [Anim.KICK, Anim.PUNCH, Anim.PICKUP, Anim.DIE,
	Anim.ZEN, Anim.CORNERED]


## Sound events the simulation raises. The renderer and the netcode carry them;
## the simulation only says WHAT happened, never plays anything.
##
## The resource numbers are SOUNDLST.RES's, so each maps to the original's own
## group of alternative takes — resource 100 is "dropping a bomb sounds" with
## bmdrop2 and bmdrop3 behind it.
enum SoundEffect {
	NONE = 0,
	BOMB_DROP,
	BOMB_KICK,
	BOMB_STOP,
	BOMB_BOUNCE,
	BOMB_GRAB,
	BOMB_PUNCH,
	BOMB_EXPLODE,
	PLAYER_DIED,
	GET_GOOD_POWERUP,
	GET_BAD_POWERUP,
	HURRY,
	WARP,
	TRAMPOLINE,
	BOMB_THROWN,       ## a punched or thrown bomb bouncing along
	BOMB_HIT_HEAD,     ## a flying bomb landed on somebody
	SOLID_DROP,        ## a Hurry solid tile slamming into place
	DISEASE_CAUGHT,    ## the generic disease sound
	SPOOGE,            ## after laying out a huge string of bombs
	AWESOME,           ## the 7th powerup, and every 3rd after it
	DEATH_TAUNT,       ## the gloating that follows a death
	ROUND_WIN,         ## this round has a winner
	DRAW,              ## nobody won
	MATCH_WIN,         ## somebody reached resource 310's win count
	ROULETTE_TICK,     ## the wheel's periodic tick
	ROULETTE_CLAP,     ## it landed on something good
	ROULETTE_BUZZ,     ## it landed on the clog
}

## SoundEffect -> the event name in the sound pack, which is the name
## tools/rss.py's EVENTS table gives a SOUNDLST resource range. The mapping is
## a table rather than a naming convention so that renaming an enum value
## cannot silently silence an event: scripts/audio/sfx.gd asks the pack whether
## every name here exists, and tests/test_sfx.gd asserts it.
const SOUND_EVENT := {
	SoundEffect.BOMB_DROP: "bomb_drop",
	SoundEffect.BOMB_KICK: "bomb_kick",
	SoundEffect.BOMB_STOP: "bomb_stop",
	SoundEffect.BOMB_BOUNCE: "bomb_bounce",
	SoundEffect.BOMB_GRAB: "bomb_grab",
	SoundEffect.BOMB_PUNCH: "bomb_punch",
	SoundEffect.BOMB_EXPLODE: "bomb_explode",
	SoundEffect.PLAYER_DIED: "player_died",
	SoundEffect.GET_GOOD_POWERUP: "powerup_good",
	SoundEffect.GET_BAD_POWERUP: "powerup_bad",
	SoundEffect.HURRY: "hurry",
	SoundEffect.WARP: "warp",
	SoundEffect.TRAMPOLINE: "trampoline",
	SoundEffect.BOMB_THROWN: "bomb_thrown",
	SoundEffect.BOMB_HIT_HEAD: "bomb_hit_head",
	SoundEffect.SOLID_DROP: "solid_drop",
	SoundEffect.DISEASE_CAUGHT: "disease",
	SoundEffect.SPOOGE: "spooge",
	SoundEffect.AWESOME: "awesome",
	SoundEffect.DEATH_TAUNT: "death_taunt",
	SoundEffect.ROUND_WIN: "round_win",
	SoundEffect.DRAW: "draw",
	SoundEffect.MATCH_WIN: "match_win",
	SoundEffect.ROULETTE_TICK: "roulette_tick",
	SoundEffect.ROULETTE_CLAP: "roulette_clap",
	SoundEffect.ROULETTE_BUZZ: "roulette_buzz",
}

## The per-disease event, for the twelve ranges at 3000 + 50*i. Separate from
## SOUND_EVENT because it is indexed by disease, not by effect: catching
## molasses and catching leprosy are the same EVENT to the simulation and
## different SOUNDS to the player.
static func disease_event(disease: int) -> String:
	return "disease_%d" % disease

## Team sentinel for the 31 of 67 scheme files whose -S lines omit the team
## field entirely. Not a guess at 0 or 1: team is real per-scheme data (77 of
## 360 team-bearing lines break player-index parity), so a scheme that does not
## state it has not stated it. Teamplay on such a scheme is the caller's
## problem to resolve, loudly.
const TEAM_UNSET := -1
