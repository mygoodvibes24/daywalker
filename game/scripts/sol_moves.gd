extends RefCounted
## Sol's sword moves as data: which clip each one plays and how it lands.
##
## Clip fields (clip names are the cuts made by tools/build_sol_modular.gd; times are in clip seconds,
## the build prints each clip's length, strike time and travel):
##   clip    animation in sol_modular.scn's library
##   from    where playback starts (a little before the strike: the swing reads before the hit lands)
##   to      where it fades back into locomotion
##   hit     the strike frame (the blade's fastest moment)
##   speed   playback rate (the equipped blade's speed multiplies it)
##   lunge   metres Sol travels forward with the step (the clip's root motion was taken out for this)
## Gameplay fields (player.gd):
##   dmg     damage multiplier on the blade's damage (before the PROGRESSION HOOK multipliers)
##   reach   strike reach (m, before the blade's reach bonus)
##   cd      cooldown before the next attack (s, divided by the blade's speed)
##   lock    seconds Sol is slowed / rooted by the move
##   shake / stop   camera shake and hit-stop (slow-mo seconds) when it connects
##   delay   true: damage lands on the clip's strike frame (every attack, the combo included: player.gd
##           buffers a press for ATTACK_BUFFER s so chaining still feels instant); false: on the press
##
## Adding a move: give the build tool its clip (assets/characters/sol/sol_mod_anim_<name>.glb, and a
## CUTS row if it should be cut), then add a row here; COMBOS lists the steps of each combo chain.

const MOVES := {
	# the light combo: Triple_Combo_Attack cut in three
	# (from -> hit is ~0.1 s of game time: the blade visibly travels before the damage lands)
	"light1": {"clip": "combo1", "from": 0.4, "to": 0.88, "hit": 0.55, "speed": 1.5, "lunge": 0.5,
		"dmg": 1.0, "reach": 2.7, "cd": 0.22, "lock": 0.22, "shake": 0.12, "stop": 0.05, "delay": true},
	"light2": {"clip": "combo2", "from": 0.25, "to": 0.68, "hit": 0.4, "speed": 1.5, "lunge": 0.65,
		"dmg": 1.0, "reach": 2.7, "cd": 0.22, "lock": 0.22, "shake": 0.12, "stop": 0.05, "delay": true},
	"light3": {"clip": "combo3", "from": 0.22, "to": 1.05, "hit": 0.37, "speed": 1.3, "lunge": 0.75,
		"dmg": 2.0, "reach": 3.3, "cd": 0.4, "lock": 0.22, "shake": 0.28, "stop": 0.09, "delay": true},
	# heavy blades (the cleaver family): Weapon_Combo_2 cut in three
	"heavy1": {"clip": "heavy1", "from": 0.5, "to": 1.0, "hit": 0.65, "speed": 1.35, "lunge": 0.45,
		"dmg": 1.0, "reach": 2.7, "cd": 0.22, "lock": 0.22, "shake": 0.14, "stop": 0.05, "delay": true},
	"heavy2": {"clip": "heavy2", "from": 0.27, "to": 0.82, "hit": 0.42, "speed": 1.35, "lunge": 0.55,
		"dmg": 1.0, "reach": 2.7, "cd": 0.22, "lock": 0.22, "shake": 0.14, "stop": 0.05, "delay": true},
	"heavy3": {"clip": "heavy3", "from": 0.38, "to": 1.15, "hit": 0.55, "speed": 1.2, "lunge": 0.6,
		"dmg": 2.0, "reach": 3.3, "cd": 0.4, "lock": 0.22, "shake": 0.3, "stop": 0.09, "delay": true},
	# hold attack: Charged_Slash from the end of its wind-up (the hold itself is the first part)
	"charged": {"clip": "charged", "from": 0.6, "to": 1.85, "hit": 1.2, "speed": 1.0, "lunge": 0.6,
		"dmg": 2.8, "reach": 3.4, "cd": 0.5, "lock": 0.85, "shake": 0.36, "stop": 0.12, "delay": true},
	# attack during / just after a Blood Dash: Thrust_Slash
	"dash": {"clip": "thrust", "from": 0.18, "to": 1.0, "hit": 0.45, "speed": 1.35, "lunge": 2.2,
		"dmg": 1.6, "reach": 3.4, "cd": 0.45, "lock": 0.45, "shake": 0.22, "stop": 0.07, "delay": true},
	# attack while sprinting: Right_Hand_Sword_Slash
	"sprint": {"clip": "quick_slash", "from": 0.28, "to": 0.95, "hit": 0.45, "speed": 1.35, "lunge": 1.4,
		"dmg": 1.3, "reach": 3.0, "cd": 0.3, "lock": 0.3, "shake": 0.16, "stop": 0.05, "delay": true},
	# attack on a staggered enemy: Sword_Judgment, the execution
	"finisher": {"clip": "judgment", "from": 0.12, "to": 1.75, "hit": 0.72, "speed": 1.1, "lunge": 0.35,
		"dmg": 1.0, "reach": 3.0, "cd": 0.3, "lock": 1.45, "shake": 0.4, "stop": 0.16, "delay": true},
	# the parry guard: Sword_Parry (no damage; player.gd runs the parry window)
	"parry": {"clip": "parry", "from": 0.05, "to": 0.75, "hit": 0.3, "speed": 1.4, "lunge": 0.0,
		"dmg": 0.0, "reach": 0.0, "cd": 0.45, "lock": 0.3, "shake": 0.0, "stop": 0.0, "delay": false},
}

## Combo chains: the steps pressed in a row (combo_t keeps the chain alive between presses).
const COMBOS := {
	"light": ["light1", "light2", "light3"],
	"heavy": ["heavy1", "heavy2", "heavy3"],
}

## If a clip is missing (an older build), the old forward / reversed slash stands in.
const FALLBACK := {"clip": "slash", "from": 0.12, "to": 0.68, "hit": 0.32, "speed": 1.6, "lunge": 0.7}
const FALLBACK_BACK := {"clip": "slash_back", "from": 0.2, "to": 0.68, "hit": 0.38, "speed": 1.6, "lunge": 0.7}


## The Arsenal (round 4): the new weapon types' chains, combo routes and Weapon Arts live in
## items/arsenal_moves.gd, in the same row format; move() and combo_step() look there too.
const ArsenalMoves = preload("res://scripts/items/arsenal_moves.gd")


static func move(name: String) -> Dictionary:
	if MOVES.has(name):
		return MOVES[name]
	return ArsenalMoves.MOVES.get(name, MOVES.light1)


static func has_move(name: String) -> bool:
	return MOVES.has(name) or ArsenalMoves.MOVES.has(name)


static func chain(chain_name: String) -> Array:
	if COMBOS.has(chain_name):
		return COMBOS[chain_name]
	return ArsenalMoves.COMBOS.get(chain_name, COMBOS.light)


## How many presses a chain has (3, or 4 for the twin stakes).
static func chain_len(chain_name: String) -> int:
	return chain(chain_name).size()


## The combo step for press number `combo` (1-based) of a chain.
static func combo_step(chain_name: String, combo: int) -> String:
	var steps: Array = chain(chain_name)
	return steps[clampi(combo - 1, 0, steps.size() - 1)]
