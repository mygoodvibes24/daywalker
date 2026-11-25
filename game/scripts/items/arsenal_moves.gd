extends RefCounted
## The Arsenal's moves as data (round 4): the combo chains of the new weapon types, their held heavies,
## the special combo routes and the Weapon Arts. Same row format as sol_moves.gd (clip, from, to, hit,
## speed, lunge, dmg, reach, cd, lock, shake, stop, delay), which looks rows up here too, plus:
##
##   arc       the strike's cone: hit if dot(forward, to enemy) > arc (0.3 default; -1.01 = all round)
##   hits      [[clip s, damage mult], ...] for a multi-hit move (the first one is the row's own strike;
##             arsenal.gd lands the rest on their frames)
##   poise     stagger multiplier on top of the weapon type's (default 1)
##   aoe       radius of a ground shockwave on the strike frame (hits everything in it)
##   heavy     true: a held heavy (player.gd treats it like the charged slash: it staggers)
##   leap      upward speed (m/s) given at the start (sprint heavy, the leaping slam)
##   invuln    seconds Sol is untouchable from the start
##   phase     true: Sol passes through enemies while it plays (the dash-through flurry)
##   stamina_cost   stamina the move spends (Group B's stamina; arsenal_data.gd scales it per type)
##
## Clip names are the cuts made by tools/build_sol_modular.gd (see its CUTS table and the clip lengths
## it prints). The three Arsenal clips: hammer / hammer_slam (Heavy_Hammer_Swing), axe_spin / axe_sweep
## (Axe_Spin_Attack), dspin / dspin_a / dspin_b (Double_Blade_Spin). Everything else re-cuts and re-times
## Sol's older clips.

const MOVES := {
	# ------------------------------------------------------------ katana: fast, bleeding cuts
	"kt1": {"clip": "combo1", "from": 0.42, "to": 0.85, "hit": 0.55, "speed": 1.55, "lunge": 0.55,
		"dmg": 0.85, "reach": 2.8, "cd": 0.18, "lock": 0.18, "shake": 0.1, "stop": 0.04, "delay": true, "stamina_cost": 9.0},
	"kt2": {"clip": "quick_slash", "from": 0.3, "to": 0.85, "hit": 0.45, "speed": 1.6, "lunge": 0.6,
		"dmg": 0.85, "reach": 2.9, "cd": 0.18, "lock": 0.18, "shake": 0.1, "stop": 0.04, "delay": true, "stamina_cost": 9.0},
	"kt3": {"clip": "combo3", "from": 0.22, "to": 1.0, "hit": 0.37, "speed": 1.45, "lunge": 0.9,
		"dmg": 1.7, "reach": 3.3, "cd": 0.34, "lock": 0.2, "shake": 0.24, "stop": 0.08, "delay": true, "stamina_cost": 13.0},
	"kt_charged": {"knock": true, "clip": "quick_slash", "from": 0.1, "to": 1.0, "hit": 0.45, "speed": 1.1, "lunge": 2.0, "heavy": true,
		"dmg": 2.4, "reach": 3.6, "cd": 0.4, "lock": 0.55, "shake": 0.32, "stop": 0.11, "delay": true, "stamina_cost": 22.0},
	# ------------------------------------------------------------ twin stakes: very fast, four hits
	"dg1": {"clip": "combo1", "from": 0.45, "to": 0.8, "hit": 0.55, "speed": 1.9, "lunge": 0.45,
		"dmg": 0.55, "reach": 2.3, "cd": 0.12, "lock": 0.14, "shake": 0.07, "stop": 0.03, "delay": true, "stamina_cost": 6.0},
	"dg2": {"clip": "combo2", "from": 0.28, "to": 0.62, "hit": 0.4, "speed": 1.9, "lunge": 0.5,
		"dmg": 0.55, "reach": 2.3, "cd": 0.12, "lock": 0.14, "shake": 0.07, "stop": 0.03, "delay": true, "stamina_cost": 6.0},
	"dg3": {"clip": "dspin_a", "from": 0.05, "to": 0.8, "hit": 0.2, "speed": 1.6, "lunge": 1.0, "hits": [[0.2, 0.5], [0.6, 0.6]],
		"dmg": 0.5, "reach": 2.4, "cd": 0.2, "lock": 0.2, "shake": 0.08, "stop": 0.03, "delay": true, "stamina_cost": 8.0},
	"dg4": {"clip": "dspin_b", "from": 0.2, "to": 0.85, "hit": 0.35, "speed": 1.5, "lunge": 0.5, "hits": [[0.35, 0.6], [0.55, 0.9]],
		"dmg": 0.6, "reach": 2.6, "arc": 0.0, "cd": 0.32, "lock": 0.22, "shake": 0.18, "stop": 0.07, "delay": true, "stamina_cost": 10.0},
	"dg_charged": {"clip": "dspin", "from": 0.1, "to": 1.65, "hit": 0.25, "speed": 1.4, "lunge": 1.9, "heavy": true,
		"hits": [[0.25, 0.5], [0.65, 0.5], [1.15, 0.6], [1.35, 0.9]],
		"dmg": 0.5, "reach": 2.6, "arc": -0.2, "cd": 0.4, "lock": 0.9, "shake": 0.22, "stop": 0.06, "delay": true, "stamina_cost": 20.0},
	# ------------------------------------------------------------ greatsword: slow, heavy stagger
	"gs1": {"clip": "heavy1", "from": 0.45, "to": 1.05, "hit": 0.65, "speed": 1.0, "lunge": 0.5, "poise": 1.2,
		"dmg": 1.35, "reach": 3.4, "arc": 0.1, "cd": 0.32, "lock": 0.3, "shake": 0.2, "stop": 0.07, "delay": true, "stamina_cost": 16.0},
	"gs2": {"clip": "heavy2", "from": 0.2, "to": 0.85, "hit": 0.42, "speed": 1.0, "lunge": 0.6, "poise": 1.2,
		"dmg": 1.35, "reach": 3.4, "arc": 0.1, "cd": 0.32, "lock": 0.3, "shake": 0.2, "stop": 0.07, "delay": true, "stamina_cost": 16.0},
	"gs3": {"clip": "hammer_slam", "from": 0.1, "to": 0.82, "hit": 0.5, "speed": 1.0, "lunge": 0.5, "poise": 1.5, "aoe": 2.2,
		"dmg": 2.4, "reach": 3.6, "arc": 0.1, "cd": 0.5, "lock": 0.45, "shake": 0.38, "stop": 0.12, "delay": true, "stamina_cost": 24.0},
	"gs_charged": {"knock": true, "clip": "charged", "from": 0.6, "to": 1.85, "hit": 1.2, "speed": 0.85, "lunge": 0.6, "heavy": true, "aoe": 2.4,
		"dmg": 3.4, "reach": 3.8, "cd": 0.6, "lock": 1.0, "shake": 0.45, "stop": 0.14, "delay": true, "stamina_cost": 32.0},
	# ------------------------------------------------------------ halberd: reach and thrusts
	"hb1": {"clip": "thrust", "from": 0.25, "to": 0.9, "hit": 0.45, "speed": 1.45, "lunge": 0.8,
		"dmg": 1.05, "reach": 4.3, "arc": 0.75, "cd": 0.22, "lock": 0.22, "shake": 0.12, "stop": 0.05, "delay": true, "stamina_cost": 12.0},
	"hb2": {"clip": "axe_sweep", "from": 0.05, "to": 0.7, "hit": 0.33, "speed": 1.3, "lunge": 0.3,
		"dmg": 1.0, "reach": 4.0, "arc": -0.2, "cd": 0.24, "lock": 0.24, "shake": 0.14, "stop": 0.05, "delay": true, "stamina_cost": 13.0},
	"hb3": {"clip": "thrust", "from": 0.2, "to": 1.1, "hit": 0.45, "speed": 1.25, "lunge": 1.4,
		"dmg": 1.9, "reach": 4.6, "arc": 0.7, "cd": 0.4, "lock": 0.3, "shake": 0.26, "stop": 0.09, "delay": true, "stamina_cost": 17.0},
	"hb_charged": {"knock": true, "clip": "thrust", "from": 0.1, "to": 1.1, "hit": 0.45, "speed": 0.95, "lunge": 2.4, "heavy": true,
		"dmg": 2.6, "reach": 4.8, "arc": 0.7, "cd": 0.5, "lock": 0.7, "shake": 0.34, "stop": 0.12, "delay": true, "stamina_cost": 26.0},
	# ------------------------------------------------------------ scythe: wide sweeps
	"sc1": {"clip": "axe_sweep", "from": 0.05, "to": 0.7, "hit": 0.33, "speed": 1.35, "lunge": 0.3,
		"dmg": 0.95, "reach": 3.7, "arc": -0.35, "cd": 0.22, "lock": 0.22, "shake": 0.12, "stop": 0.05, "delay": true, "stamina_cost": 12.0},
	"sc2": {"clip": "slash_back", "from": 0.2, "to": 0.68, "hit": 0.38, "speed": 1.4, "lunge": 0.45,
		"dmg": 0.95, "reach": 3.7, "arc": -0.1, "cd": 0.22, "lock": 0.22, "shake": 0.12, "stop": 0.05, "delay": true, "stamina_cost": 12.0},
	"sc3": {"clip": "axe_spin", "from": 0.2, "to": 1.4, "hit": 0.55, "speed": 1.35, "lunge": 0.5, "hits": [[0.55, 0.8], [0.83, 1.2]],
		"dmg": 0.8, "reach": 3.9, "arc": -1.01, "cd": 0.4, "lock": 0.35, "shake": 0.24, "stop": 0.08, "delay": true, "stamina_cost": 18.0},
	"sc_charged": {"clip": "axe_spin", "from": 0.1, "to": 1.45, "hit": 0.55, "speed": 1.1, "lunge": 0.6, "heavy": true,
		"hits": [[0.55, 0.9], [0.83, 1.4]],
		"dmg": 0.9, "reach": 4.0, "arc": -1.01, "cd": 0.5, "lock": 0.9, "shake": 0.32, "stop": 0.1, "delay": true, "stamina_cost": 26.0},
	# ------------------------------------------------------------ war hammer: armour and wolf break
	"hm1": {"clip": "heavy2", "from": 0.2, "to": 0.85, "hit": 0.42, "speed": 1.05, "lunge": 0.45, "poise": 1.2,
		"dmg": 1.3, "reach": 2.9, "cd": 0.3, "lock": 0.3, "shake": 0.2, "stop": 0.07, "delay": true, "stamina_cost": 16.0},
	"hm2": {"clip": "slash_back", "from": 0.15, "to": 0.68, "hit": 0.38, "speed": 1.15, "lunge": 0.45, "poise": 1.2,
		"dmg": 1.3, "reach": 2.9, "cd": 0.3, "lock": 0.3, "shake": 0.2, "stop": 0.07, "delay": true, "stamina_cost": 16.0},
	"hm3": {"clip": "hammer", "from": 0.75, "to": 1.57, "hit": 1.25, "speed": 1.2, "lunge": 0.5, "poise": 1.8, "aoe": 2.6,
		"dmg": 2.6, "reach": 3.1, "cd": 0.55, "lock": 0.5, "shake": 0.45, "stop": 0.13, "delay": true, "stamina_cost": 26.0},
	"hm_charged": {"knock": true, "clip": "hammer", "from": 0.3, "to": 1.57, "hit": 1.25, "speed": 1.05, "lunge": 0.5, "heavy": true, "poise": 2.0, "aoe": 3.2,
		"dmg": 3.4, "reach": 3.2, "cd": 0.6, "lock": 1.1, "shake": 0.5, "stop": 0.15, "delay": true, "stamina_cost": 34.0},
	# ------------------------------------------------------------ chain-whip: mid range lashes
	"wh1": {"clip": "slash", "from": 0.12, "to": 0.62, "hit": 0.32, "speed": 1.5, "lunge": 0.2,
		"dmg": 0.85, "reach": 4.8, "arc": 0.15, "cd": 0.22, "lock": 0.2, "shake": 0.1, "stop": 0.04, "delay": true, "stamina_cost": 10.0},
	"wh2": {"clip": "slash_back", "from": 0.18, "to": 0.64, "hit": 0.38, "speed": 1.5, "lunge": 0.2,
		"dmg": 0.85, "reach": 4.8, "arc": 0.15, "cd": 0.22, "lock": 0.2, "shake": 0.1, "stop": 0.04, "delay": true, "stamina_cost": 10.0},
	"wh3": {"clip": "axe_sweep", "from": 0.05, "to": 0.72, "hit": 0.33, "speed": 1.3, "lunge": 0.2,
		"dmg": 1.5, "reach": 5.2, "arc": -0.5, "cd": 0.38, "lock": 0.26, "shake": 0.2, "stop": 0.07, "delay": true, "stamina_cost": 15.0},
	"wh_charged": {"clip": "axe_spin", "from": 0.2, "to": 1.4, "hit": 0.55, "speed": 1.2, "lunge": 0.3, "heavy": true,
		"hits": [[0.55, 0.8], [0.83, 1.2]],
		"dmg": 0.8, "reach": 5.0, "arc": -1.01, "cd": 0.5, "lock": 0.85, "shake": 0.28, "stop": 0.09, "delay": true, "stamina_cost": 22.0},

	# ============================================================ special combo routes (arsenal.gd)
	# tap, tap, HOLD: the chain's finisher
	"ls_llh": {"clip": "thrust", "from": 0.2, "to": 1.05, "hit": 0.45, "speed": 1.3, "lunge": 1.6, "poise": 1.5,
		"dmg": 2.6, "reach": 3.8, "arc": 0.6, "cd": 0.45, "lock": 0.5, "shake": 0.34, "stop": 0.12, "stamina_cost": 22.0, "title": "SILVER LANCE"},
	"cl_llh": {"clip": "hammer_slam", "from": 0.1, "to": 0.82, "hit": 0.5, "speed": 1.05, "lunge": 0.6, "aoe": 2.2, "poise": 1.5,
		"dmg": 2.8, "reach": 3.0, "cd": 0.5, "lock": 0.55, "shake": 0.42, "stop": 0.13, "stamina_cost": 26.0, "title": "BUTCHER'S DROP"},
	"kt_llh": {"clip": "judgment", "from": 0.3, "to": 1.4, "hit": 0.72, "speed": 1.4, "lunge": 0.9,
		"dmg": 2.6, "reach": 3.3, "arc": 0.2, "cd": 0.45, "lock": 0.6, "shake": 0.34, "stop": 0.12, "stamina_cost": 20.0, "title": "MOON DRAW"},
	"dg_llh": {"clip": "dspin", "from": 0.1, "to": 1.65, "hit": 0.25, "speed": 1.5, "lunge": 2.4,
		"hits": [[0.25, 0.7], [0.65, 0.7], [1.15, 0.8], [1.35, 1.2]],
		"dmg": 0.75, "reach": 2.6, "arc": -0.3, "cd": 0.45, "lock": 0.8, "shake": 0.24, "stop": 0.07, "stamina_cost": 22.0, "title": "STAKE STORM"},
	"gs_llh": {"clip": "hammer", "from": 0.75, "to": 1.57, "hit": 1.25, "speed": 1.15, "lunge": 0.8, "aoe": 2.6, "poise": 1.6,
		"dmg": 3.0, "reach": 3.6, "cd": 0.55, "lock": 0.6, "shake": 0.5, "stop": 0.15, "stamina_cost": 32.0, "title": "CATHEDRAL FALL"},
	"hb_llh": {"clip": "axe_spin", "from": 0.2, "to": 1.4, "hit": 0.55, "speed": 1.3, "lunge": 0.6, "hits": [[0.55, 0.9], [0.83, 1.3]],
		"dmg": 1.3, "reach": 4.4, "arc": -1.01, "cd": 0.5, "lock": 0.7, "shake": 0.3, "stop": 0.1, "stamina_cost": 24.0, "title": "LEVEE SWEEP"},
	"sc_llh": {"clip": "axe_spin", "from": 0.2, "to": 1.4, "hit": 0.55, "speed": 1.45, "lunge": 0.7, "hits": [[0.55, 1.0], [0.83, 1.4]],
		"dmg": 1.3, "reach": 4.1, "arc": -1.01, "cd": 0.5, "lock": 0.65, "shake": 0.3, "stop": 0.1, "stamina_cost": 24.0, "title": "REAPING CIRCLE"},
	"hm_llh": {"clip": "hammer_slam", "from": 0.1, "to": 0.82, "hit": 0.5, "speed": 1.1, "lunge": 0.6, "aoe": 3.0, "poise": 2.0,
		"dmg": 3.0, "reach": 3.2, "cd": 0.55, "lock": 0.6, "shake": 0.5, "stop": 0.15, "stamina_cost": 32.0, "title": "ANVIL"},
	"wh_llh": {"clip": "axe_spin", "from": 0.2, "to": 1.4, "hit": 0.55, "speed": 1.3, "lunge": 0.3, "hits": [[0.55, 0.9], [0.83, 1.3]],
		"dmg": 1.2, "reach": 5.4, "arc": -1.01, "cd": 0.5, "lock": 0.65, "shake": 0.28, "stop": 0.1, "stamina_cost": 22.0, "title": "CENSER RING"},
	# hold through the thrust out of a Blood Dash: the heavy after a dodge
	"ls_dodge": {"clip": "charged", "from": 1.0, "to": 1.85, "hit": 1.2, "speed": 1.2, "lunge": 1.0, "poise": 1.6,
		"dmg": 2.3, "reach": 3.4, "cd": 0.45, "lock": 0.5, "shake": 0.32, "stop": 0.11, "stamina_cost": 20.0, "title": "REVERSAL"},
	"kt_dodge": {"clip": "dspin_b", "from": 0.2, "to": 0.85, "hit": 0.35, "speed": 1.35, "lunge": 1.2, "hits": [[0.35, 1.1], [0.55, 1.3]],
		"dmg": 1.1, "reach": 3.0, "arc": 0.0, "cd": 0.4, "lock": 0.45, "shake": 0.28, "stop": 0.1, "stamina_cost": 18.0, "title": "SHADOW CUT"},
	"dg_dodge": {"clip": "dspin_a", "from": 0.0, "to": 0.85, "hit": 0.2, "speed": 1.5, "lunge": 1.6, "hits": [[0.2, 0.9], [0.6, 1.0]],
		"dmg": 0.9, "reach": 2.6, "arc": -0.2, "cd": 0.35, "lock": 0.4, "shake": 0.2, "stop": 0.07, "stamina_cost": 14.0, "title": "PINNING STAKES"},
	"gs_dodge": {"clip": "charged", "from": 1.0, "to": 1.85, "hit": 1.2, "speed": 1.0, "lunge": 0.9, "aoe": 2.0, "poise": 1.6,
		"dmg": 3.0, "reach": 3.6, "cd": 0.55, "lock": 0.6, "shake": 0.42, "stop": 0.13, "stamina_cost": 28.0, "title": "REVERSAL"},
	"hb_dodge": {"clip": "axe_sweep", "from": 0.0, "to": 0.72, "hit": 0.33, "speed": 1.2, "lunge": 0.6,
		"dmg": 2.0, "reach": 4.4, "arc": -0.5, "cd": 0.45, "lock": 0.5, "shake": 0.3, "stop": 0.1, "stamina_cost": 20.0, "title": "HOOKING SWEEP"},
	"sc_dodge": {"clip": "axe_sweep", "from": 0.0, "to": 0.72, "hit": 0.33, "speed": 1.25, "lunge": 0.6,
		"dmg": 2.0, "reach": 4.0, "arc": -0.6, "cd": 0.45, "lock": 0.5, "shake": 0.3, "stop": 0.1, "stamina_cost": 20.0, "title": "HOOKING SWEEP"},
	"wh_dodge": {"clip": "axe_sweep", "from": 0.0, "to": 0.72, "hit": 0.33, "speed": 1.25, "lunge": 0.3,
		"dmg": 1.8, "reach": 5.2, "arc": -0.6, "cd": 0.45, "lock": 0.5, "shake": 0.28, "stop": 0.1, "stamina_cost": 18.0, "title": "RECOIL LASH"},
	# hold through the running slash: the sprint heavy
	"ls_sprint": {"clip": "charged", "from": 1.0, "to": 1.85, "hit": 1.2, "speed": 1.15, "lunge": 3.0, "leap": 6.5, "aoe": 1.8, "poise": 1.4,
		"dmg": 2.6, "reach": 3.4, "cd": 0.5, "lock": 0.6, "shake": 0.38, "stop": 0.12, "stamina_cost": 24.0, "title": "LEAPING CUT"},
	"hv_sprint": {"clip": "hammer_slam", "from": 0.05, "to": 0.82, "hit": 0.5, "speed": 1.0, "lunge": 3.2, "leap": 6.5, "aoe": 2.6, "poise": 1.6,
		"dmg": 3.0, "reach": 3.2, "cd": 0.55, "lock": 0.65, "shake": 0.45, "stop": 0.14, "stamina_cost": 30.0, "title": "LEAPING CLEAVE"},
	"dg_sprint": {"clip": "dspin", "from": 0.1, "to": 1.65, "hit": 0.25, "speed": 1.55, "lunge": 3.5,
		"hits": [[0.25, 0.6], [0.65, 0.6], [1.15, 0.7], [1.35, 1.0]],
		"dmg": 0.75, "reach": 2.6, "arc": -0.3, "cd": 0.45, "lock": 0.75, "shake": 0.22, "stop": 0.06, "stamina_cost": 20.0, "title": "RUNNING FLURRY"},
	"hb_sprint": {"clip": "thrust", "from": 0.15, "to": 1.1, "hit": 0.45, "speed": 1.1, "lunge": 4.5, "poise": 1.6,
		"dmg": 2.4, "reach": 4.6, "arc": 0.6, "cd": 0.5, "lock": 0.6, "shake": 0.36, "stop": 0.12, "stamina_cost": 24.0, "title": "LANCE CHARGE"},
	"hm_sprint": {"clip": "hammer", "from": 0.75, "to": 1.57, "hit": 1.25, "speed": 1.15, "lunge": 3.2, "leap": 7.0, "aoe": 3.0, "poise": 2.0,
		"dmg": 3.2, "reach": 3.2, "cd": 0.6, "lock": 0.7, "shake": 0.5, "stop": 0.15, "stamina_cost": 32.0, "title": "METEOR"},
	"wh_sprint": {"clip": "axe_spin", "from": 0.2, "to": 1.4, "hit": 0.55, "speed": 1.3, "lunge": 2.0, "hits": [[0.55, 0.9], [0.83, 1.3]],
		"dmg": 1.1, "reach": 5.2, "arc": -1.01, "cd": 0.5, "lock": 0.6, "shake": 0.28, "stop": 0.1, "stamina_cost": 22.0, "title": "WHEELING LASH"},
	# in the air: a cut that hangs Sol for a breath, and the plunge (hold) that dives and bursts on landing
	"jump_cut": {"clip": "slash", "from": 0.12, "to": 0.62, "hit": 0.32, "speed": 1.5, "lunge": 0.8, "hang": 0.25,
		"dmg": 1.25, "reach": 3.0, "arc": 0.1, "cd": 0.3, "lock": 0.25, "shake": 0.16, "stop": 0.05, "stamina_cost": 12.0, "title": ""},
	"plunge": {"clip": "hammer_slam", "from": 0.05, "to": 0.82, "hit": 0.5, "speed": 1.0, "lunge": 0.6, "plunge": true, "aoe": 3.0, "poise": 1.8,
		"dmg": 2.4, "reach": 3.0, "arc": -1.01, "cd": 0.45, "lock": 0.55, "shake": 0.45, "stop": 0.14, "stamina_cost": 22.0, "title": "PLUNGE"},
	"plunge_heavy": {"clip": "hammer_slam", "from": 0.05, "to": 0.82, "hit": 0.5, "speed": 1.0, "lunge": 0.6, "plunge": true, "aoe": 4.2, "poise": 2.4,
		"dmg": 3.2, "reach": 3.2, "arc": -1.01, "cd": 0.5, "lock": 0.6, "shake": 0.55, "stop": 0.16, "stamina_cost": 28.0, "title": "CRATER"},
	# attack right after a parry: the riposte (a crit on the parried enemy)
	"riposte": {"clip": "thrust", "from": 0.22, "to": 1.0, "hit": 0.45, "speed": 1.6, "lunge": 1.2, "crit": 3.5,
		"dmg": 1.0, "reach": 3.4, "arc": 0.4, "cd": 0.4, "lock": 0.45, "invuln": 0.5, "shake": 0.45, "stop": 0.18, "stamina_cost": 0.0, "title": "RIPOSTE"},
	# the blood-chain: the Weapon Art button right after the third hit spends blood for this finisher
	"blood_chain": {"clip": "judgment", "from": 0.3, "to": 1.5, "hit": 0.72, "speed": 1.35, "lunge": 0.7, "aoe": 3.0, "poise": 2.0,
		"dmg": 3.2, "reach": 3.6, "arc": -0.2, "cd": 0.45, "lock": 0.75, "invuln": 0.6, "shake": 0.5, "stop": 0.18, "bleed": 200.0,
		"stamina_cost": 0.0, "title": "BLOOD CHAIN"},

	# ============================================================ Weapon Arts (the moves the ARTS play)
	"art_nova": {"clip": "charged", "from": 0.3, "to": 1.85, "hit": 1.2, "speed": 1.25, "lunge": 0.2, "invuln": 0.4,
		"dmg": 2.2, "reach": 5.0, "arc": -1.01, "poise": 2.0, "cd": 0.5, "lock": 1.0, "shake": 0.45, "stop": 0.16},
	"art_wave": {"clip": "quick_slash", "from": 0.2, "to": 1.0, "hit": 0.45, "speed": 1.3, "lunge": 0.3,
		"dmg": 2.0, "reach": 0.0, "cd": 0.35, "lock": 0.4, "shake": 0.22, "stop": 0.05},
	"art_flurry": {"clip": "dspin", "from": 0.15, "to": 1.7, "hit": 0.25, "speed": 1.6, "lunge": 6.0, "invuln": 0.9, "phase": true,
		"hits": [[0.25, 0.6], [0.45, 0.5], [0.65, 0.6], [0.95, 0.5], [1.15, 0.7], [1.35, 1.1]],
		"dmg": 0.8, "reach": 2.6, "arc": -1.01, "cd": 0.4, "lock": 0.9, "shake": 0.25, "stop": 0.05, "bleed": 25.0},
	"art_launch": {"clip": "combo3", "from": 0.2, "to": 1.2, "hit": 0.37, "speed": 1.15, "lunge": 0.6, "leap": 6.0, "launch": 9.0,
		"dmg": 2.6, "reach": 3.5, "arc": 0.1, "poise": 3.0, "cd": 0.45, "lock": 0.6, "shake": 0.4, "stop": 0.14},
	"art_rush": {"clip": "thrust", "from": 0.15, "to": 1.2, "hit": 0.45, "speed": 1.0, "lunge": 7.5, "invuln": 0.5, "phase": true,
		"hits": [[0.3, 0.6], [0.38, 0.6], [0.45, 1.2]],
		"dmg": 1.5, "reach": 2.6, "arc": 0.3, "poise": 2.0, "cd": 0.5, "lock": 0.75, "shake": 0.38, "stop": 0.12},
	"art_whirl": {"clip": "axe_spin", "from": 0.1, "to": 1.5, "hit": 0.4, "speed": 1.2, "lunge": 1.2,
		"hits": [[0.4, 0.7], [0.6, 0.7], [0.83, 1.0], [1.0, 0.8], [1.15, 0.8]],
		"dmg": 1.0, "reach": 4.2, "arc": -1.01, "cd": 0.4, "lock": 0.7, "shake": 0.25, "stop": 0.05, "bleed": 20.0},
	"art_slam": {"clip": "hammer", "from": 0.3, "to": 1.57, "hit": 1.25, "speed": 1.15, "lunge": 4.5, "leap": 10.0, "invuln": 0.7,
		"aoe": 5.0, "poise": 3.0, "dmg": 3.0, "reach": 3.4, "arc": -1.01, "cd": 0.5, "lock": 1.1, "shake": 0.6, "stop": 0.18},
	"art_lash": {"clip": "slash", "from": 0.1, "to": 0.66, "hit": 0.32, "speed": 1.3, "lunge": 0.0,
		"dmg": 1.4, "reach": 10.0, "arc": 0.45, "cd": 0.35, "lock": 0.4, "shake": 0.3, "stop": 0.1},
	"art_cleave": {"clip": "hammer_slam", "from": 0.05, "to": 0.82, "hit": 0.5, "speed": 1.0, "lunge": 0.4,
		"dmg": 2.4, "reach": 0.0, "poise": 2.0, "cd": 0.45, "lock": 0.6, "shake": 0.5, "stop": 0.14, "bleed": 40.0},
}

## The light chains of the new weapon types (sol_moves.gd COMBOS holds light and heavy).
const COMBOS := {
	"katana": ["kt1", "kt2", "kt3"],
	"daggers": ["dg1", "dg2", "dg3", "dg4"],
	"great": ["gs1", "gs2", "gs3"],
	"halberd": ["hb1", "hb2", "hb3"],
	"scythe": ["sc1", "sc2", "sc3"],
	"hammer": ["hm1", "hm2", "hm3"],
	"whip": ["wh1", "wh2", "wh3"],
}

## Weapon Arts: name, the move it plays, cooldown (s), blood cost (HP) and what it does (arsenal.gd).
const ARTS := {
	"silver_nova": {"name": "Silver Nova", "move": "art_nova", "cd": 9.0, "blood": 0.0, "fx": "nova",
		"desc": "Raise the blade and burst into a ring of silver light that throws back everything within 5 m."},
	"blood_wave": {"name": "Blood Wave", "move": "art_wave", "cd": 3.5, "blood": 6.0, "fx": "wave",
		"desc": "Cut the air: a crescent of your own blood flies 16 m, slicing all it passes and soaking them in Bleed."},
	"crimson_flurry": {"name": "Crimson Flurry", "move": "art_flurry", "cd": 7.0, "blood": 0.0, "fx": "flurry",
		"desc": "Dash through the crowd, untouchable, stakes spinning, striking everything you pass."},
	"rising_launcher": {"name": "Rising Launcher", "move": "art_launch", "cd": 7.0, "blood": 0.0, "fx": "launch",
		"desc": "A burning rising cut that hurls enemies into the air and breaks their guard."},
	"impaling_rush": {"name": "Impaling Rush", "move": "art_rush", "cd": 6.0, "blood": 0.0, "fx": "rush",
		"desc": "Charge 7 m with the spear-point leading, skewering every enemy in the line."},
	"whirlwind": {"name": "Whirlwind", "move": "art_whirl", "cd": 7.0, "blood": 5.0, "fx": "whirl",
		"desc": "Spin the scythe in a full circle five times over, reaping everything around you."},
	"leaping_slam": {"name": "Leaping Slam", "move": "art_slam", "cd": 9.0, "blood": 0.0, "fx": "slam",
		"desc": "Leap high and bring the hammer down: a 5 m shockwave that staggers wolves and shatters guards."},
	"chain_lash": {"name": "Chain Lash", "move": "art_lash", "cd": 5.0, "blood": 0.0, "fx": "lash",
		"desc": "Lash the burning chain up to 10 m and drag the enemy to your feet, staggered."},
	"butcher_cleave": {"name": "Butcher's Cleave", "move": "art_cleave", "cd": 7.0, "blood": 8.0, "fx": "cleave",
		"desc": "Split the street: three ruptures of blood erupt in a line ahead of you."},
}

const BLOOD_CHAIN_COST := 12.0 # blood the blood-chain finisher spends
