# Sword Animation Reference

Preview clips of sword animations from the rig animation library that Higgsfield's auto-rigger (Meshy) uses. They're reference for how Sol's sword combat should move. The `.gif` files are the free previews; `sword_attacks_sheet.jpg` shows 8 frames of each side by side. These previews are the library's own reference renders (on a mannequin), kept here for study only; they don't ship in the game.

## Clips Sol owns (paid, in `game/assets/characters/sol/`)
All on the same 24-joint Meshy rig of Sol's body. The build tool (`game/tools/build_sol_modular.gd`) picks up every `sol_mod_anim_<name>.glb`, cuts them into moves (its `CUTS` table) and stores each move's strike time and travel; `game/scripts/sol_moves.gd` says how each move plays and lands.

| Clip | Library id | File | Used for |
|---|---|---|---|
| Idle_02 | 11 | `sol_mod_anim_idle02.glb` | standing: a calm, grounded breathing stance (1.9 s loop). The build stores it as `idle` (round 2: the owner disliked the old idle) |
| idle (look-around) | 0 | `sol_mod_rig_idle.glb` | stored as `idle_look`; only a rare fidget after 12 s standing still out of combat (`sol_modular_anim.gd` FIDGET_AFTER) |
| run | 14 | `sol_mod_anim_run.glb` | running |
| sprint (Lean_Forward_Sprint) | 509 | `sol_mod_anim_sprint.glb` | sprinting |
| slash (Left_Slash) | 97 | `sol_mod_anim_slash.glb` | fallback swing (and the enemies' attack) |
| hit (Hit_Reaction) | 178 | `sol_mod_anim_hit.glb` | taking damage |
| death (Dead) | 8 | `sol_mod_anim_death.glb` | dying |
| jump | 466 | `sol_mod_anim_jump.glb` | airborne |
| Triple_Combo_Attack | 105 | `sol_mod_anim_triple_combo.glb` | the light combo, cut into its 3 hits (combo1-3) |
| Thrust_Slash | 240 | `sol_mod_anim_thrust.glb` | dash attack (attack during / just after a Blood Dash) |
| Charged_Slash | 242 | `sol_mod_anim_charged.glb` | heavy attack (hold attack ~0.4 s) |
| Sword_Judgment | 102 | `sol_mod_anim_judgment.glb` | execution of a staggered enemy (trimmed to 1.8 s) |
| Sword_Parry | 147 | `sol_mod_anim_parry.glb` | parry (C / middle mouse / L3) |
| Weapon_Combo_2 | 241 | `sol_mod_anim_weapon_combo2.glb` | the combo for heavy blades (cleaver family), cut into 3 hits |
| Combat_Stance | 89 | `sol_mod_anim_stance.glb` | combat idle with enemies within 10 m |
| Right_Hand_Sword_Slash | 219 | `sol_mod_anim_quick_slash.glb` | sprint attack |
| Casual_Walk_inplace | 613 | `sol_mod_anim_walk.glb` | the walk (bought 2026-11-26, job 0e725925-830a-44cd-82e5-70474d7877d4, 8 credits): a calm stroll, 4.2 s loop, planted foot ~0.73 m/s; played at 1.5x for the 1.1 m/s walk (`sol_locomotion.gd` CLIP_SPEED) |
| Cautious_Crouch_Walk_Forward_inplace | 616 | `sol_mod_anim_crouch_walk.glb` | the crouch walk (bought 2026-11-26, job b775afe7-e189-41cb-92fc-440fbf727756, 8 credits): a low, side-on creep with the arms reaching forward, 1.17 s loop, planted foot ~1.3 m/s; played at 0.77x for the 1.0 m/s crouch walk (`sol_locomotion.gd` CLIP_SPEED) |
| CrouchLookAroundBow | 258 | `sol_mod_anim_crouch_idle.glb` | the crouch idle (bought 2026-11-26, job 21f86dc5-baf8-46bc-8421-4acc24d8c376, 8 credits): a deep squat (hips ~0.27 m lower than the crouch walk's) with a slow look around, 5.9 s loop. Its bow arms are swapped at load time for the standing idle's loose arms and its hips turned 16 deg toward the crouch walk's facing (`SolLoco._unbow_crouch_idle`) |
| Heavy_Hammer_Swing | 128 | `sol_mod_anim_hammer_swing.glb` | the Arsenal (round 4): cut into `hammer` (0.3-1.87 s, the full overhead wind-up, slam at 1.55 s) and `hammer_slam` (1.05-1.87 s, just the drop). War hammer chain finisher and heavy, the Leaping Slam art, the plunge landing, the greatsword / cleaver finishers |
| Axe_Spin_Attack | 238 | `sol_mod_anim_axe_spin.glb` | the Arsenal: cut into `axe_spin` (0.1-1.6 s, a full turn, the sweep at 0.92 s) and `axe_sweep` (0.6-1.35 s, the cut alone). Scythe and halberd sweeps, the chain-whip's circle, the Whirlwind art |
| Double_Blade_Spin | 91 | `sol_mod_anim_double_spin.glb` | the Arsenal: cut into `dspin` (0.2-1.9 s, a 1.9 m lunging flurry: right 0.45 / spin 0.85 / left 1.35 / right 1.55 s), `dspin_a` and `dspin_b` (its halves). Twin-stake chain hits 3-4 and heavy, the Crimson Flurry dash-through art |

The three Arsenal clips were bought in round 4 for 24 credits (one `3d_rigging` call each, 8 credits, on Sol's body
model at 1.88 m; jobs d0dbe736 / 8f9f079f / 564f667d). Every other Arsenal move re-cuts and re-times the clips above
(`game/scripts/items/arsenal_moves.gd` says which clip, window and speed each move uses). The build tool also adds
a `BladeL` socket in the left fist for the twin stakes.

## Locomotion: the walk, the empty arm, the crouch (round 3)
The walk and both crouch clips are bought (above; Meshy library via Higgsfield, 8 credits each, the `_inplace` versions where there is one):
- **Walk:** the bought `walk` sits on the locomotion BlendSpace1D at `WALK_SPEED` (1.1 m/s), played at `WALK_SPEED / CLIP_SPEED["walk"]`. Without it, `game/scripts/sol_locomotion.gd` `bake_walk()` builds a stand-in `walk_proc` at load time from the run (the run's cycle at 0.62 of its speed, legs pulled toward the straight rest legs, spine, head and arms toward the idle, 30% of the hips' bounce). A part-tilted stick or the walk toggle (Alt / Z) walks. Alternatives seen: walking_2_inplace (692, a feminine sway), Thoughtful_Walk (121).
- **The empty right arm:** `game/scripts/sol_arm_pose.gd` mirrors the clip's free left arm onto the right one while the sword is sheathed, with the swing flipped so the arms alternate. Every clip Sol owns has a sword grip in the right hand, so this stays.
- **Crouch:** `sol_modular_anim.gd` blends a crouch BlendSpace1D (`crouch_idle` at 0, `crouch_walk` at `CROUCH_SPEED` 1.0 m/s, played at 1.0 / 1.3 = 0.77x) in behind a Blend2, and the procedural crouch pose stays off. That pose (`game/scripts/sol_crouch_pose.gd`: hips down 0.3 m, two-bone leg IK, spine lean) is only the stand-in for a library without the crouch clips. The standing look-around fidget no longer fires while crouched. The library has no plain crouch idle (searched: crouch, sneak, kneel, the Idle category); the crouch walk's root-motion version is 524.

### The crouch idle: bought clip vs the held crouch-walk frame (2026-11-26)
Compared in contact sheets (side and three-quarter, sheathed and drawn, plus the walk-to-idle, stand-up and crouch-down transitions):
- **Held first frame of the crouch walk** (`SolLoco.ensure_crouch_idle` without a bought idle): a frozen mid-stride, one heel lifted, a stiff forward hunch with both arms out at shoulder height. It read as a paused walk, not a rest.
- **CrouchLookAroundBow as bought:** a settled, deep squat with both feet planted and a slow look around (alive), but the bow arms reach forward at chest height and the stance stands ~20 deg more side-on than the crouch walk.
- **Chosen: the bought clip, fitted** (`SolLoco._unbow_crouch_idle`, once per library at load). Its eight arm joints (both clavicles to both hands) are held at the standing idle's first frame. Sheathed, the left arm hangs loose with the fist by the knee, and `sol_arm_pose.gd` mirrors it onto the right; drawn, the right hand keeps the idle's grip, so the sword rests low and forward, a ready crouch. Its hips are turned 16 deg toward the crouch walk's mean facing, so standing up and moving off twist less. The crouch walk's arms were tried as the idle's arms too: held still they read as a sleepwalker.
- Known trade-offs: the crouch walk itself keeps its forward-reaching arms (they swing in as he moves off), and the idle squats ~0.27 m deeper than the walk, so the hips rise a little as he starts to creep.

### How to install
1. Generate the clip on Sol's body through Higgsfield: `generate_3d` with `model: 3d_rigging`, `model_url` = Sol's body GLB (https://d2ol7oe51mr4n9.cloudfront.net/user_3M3cbVYOpQkCAbZXwwBloXVahos/1cc3de5d-2289-444d-8383-29ffe7f0fd64.glb), `height_meters: 1.88`, `enable_animation: true`, `animation_action_id` from the table. Preflight with `get_cost: true` (8 credits).
2. Download the rigged GLB and strip it to the skeleton and clip: `godot --headless -s res://tools/strip_rig_glb.gd -- <download.glb> res://assets/characters/sol/sol_mod_anim_<name>.glb anim`, using the "Install as" name above (`walk`, `crouch_walk`, `crouch_idle`).
3. Import (`godot --headless --import`), then rebuild the scene: `godot --headless -s res://tools/build_sol_modular.gd`. The build picks up every `sol_mod_anim_<name>.glb` by its name; `walk`, `crouch_idle` and `crouch_walk` are already in its `LOOPED` list (looped, drift stripped).
4. Nothing else to change. `sol_modular_anim.gd` uses a clip named `walk` in place of `walk_proc` at the walk blend point. Once `crouch_walk` exists it adds a crouch BlendSpace1D (crouch idle 0 / crouch walk at `CROUCH_SPEED`) behind a Blend2 and turns the procedural crouch pose off.
5. Measure the clip's planted-foot speed (sample the foot bones while they are on the floor) into `CLIP_SPEED` in `sol_locomotion.gd`; the clip then plays at the rate that matches `WALK_SPEED` / `CROUCH_SPEED`. Run the smoke test (it checks the walk blend point and the crouch).
6. The rebuild also rewrites the four `sol_sword_*.scn` files byte-for-byte differently with the same content; restore them with git unless the swords changed. Textures are not re-exported, so `tools/sol_texture_fixes.py` doesn't need re-running (checked again for the crouch clips).

The 11 MB rig downloads stay out of the repo; `game/tools/strip_rig_glb.gd <src> <dst> anim` makes the ~50 KB skeleton-only files.

## Not recommended
- **Generated video clips** (e.g. Seedance, about 35 credits for 5 s) only give a 2D video, which the game can't play on a character. Library clips are real motion capture data that drive the skeleton directly.
- **Clips with a shield** (Left_Slash shows one in its preview) have the free arm posed for a shield; on Sol that arm swings empty. They're usable, but the clips above suit a single sword better.
