
; NOT ONE OF THE DISC'S OWN SCHEMES. Hand-authored for this port, to exercise
; every powerup and mechanic in one round without hunting for the right disc
; scheme and level. Load it with `--scheme test_data/TESTALL.SCH`; pair with
; a level that has specials (arrows/conveyors/trampolines/warps) if those are
; what is under test — a scheme has no say over which extras a level places,
; see scripts/sim/sim.gd's load_extras(). The in-game F3 test editor
; (scripts/app/main.gd/game_view.gd) covers everything a scheme cannot:
; placing a specific powerup or bomb on demand, killing/curing a player,
; and reshaping bricks live.

-V,2

-N,TEST ALL (10)

-B,100

; Sparse pillar grid — solid only on the interior's odd/odd cells — so almost
; the whole 15x11 field is destructible brick: room for the powerup counts
; below to actually land, and room to test flame length against real bricks
; rather than mostly open floor.
;               11111
;     012345678901234
-R, 0,:::::::::::::::
-R, 1,:#:#:#:#:#:#:#:
-R, 2,:::::::::::::::
-R, 3,:#:#:#:#:#:#:#:
-R, 4,:::::::::::::::
-R, 5,:#:#:#:#:#:#:#:
-R, 6,:::::::::::::::
-R, 7,:#:#:#:#:#:#:#:
-R, 8,:::::::::::::::
-R, 9,:#:#:#:#:#:#:#:
-R,10,:::::::::::::::

-S,0,1,0
-S,1,4,0
-S,2,10,0
-S,3,13,0
-S,4,13,10
-S,5,10,10
-S,6,4,10
-S,7,1,10
-S,8,5,5
-S,9,9,5

; powerup #, bornwith, has_override, override_value, forbidden, comment
; Every type overridden to a small POSITIVE count, so it is guaranteed on the
; field rather than left to VALUELST 400-412's own (often negative,
; sampled) defaults — see field.gd place_powerups(). 47 powerups total
; against ~130 brick cells, so placement never runs out of candidates.
-P, 0, 0,1, 6, 0,an extra bomb
-P, 1, 0,1, 6, 0,longer flame length
-P, 2, 0,1, 3, 0,a disease
-P, 3, 0,1, 4, 0,the ability to kick bombs
-P, 4, 0,1, 4, 0,extra speed
-P, 5, 0,1, 4, 0,the ability to punch bombs
-P, 6, 0,1, 4, 0,the ability to grab bombs
-P, 7, 0,1, 3, 0,the spooger
-P, 8, 0,1, 3, 0,goldflame
-P, 9, 0,1, 3, 0,a trigger mechanism
-P,10, 0,1, 3, 0,jelly (bouncy) bombs
-P,11, 0,1, 2, 0,super bad disease
-P,12, 0,1, 2, 0,random
