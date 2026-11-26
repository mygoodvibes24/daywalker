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
| Heavy_Hammer_Swing | 128 | `sol_mod_anim_hammer_swing.glb` | the Arsenal (round 4): cut into `hammer` (0.3-1.87 s, the full overhead wind-up, slam at 1.55 s) and `hammer_slam` (1.05-1.87 s, just the drop). War hammer chain finisher and heavy, the Leaping Slam art, the plunge landing, the greatsword / cleaver finishers |
| Axe_Spin_Attack | 238 | `sol_mod_anim_axe_spin.glb` | the Arsenal: cut into `axe_spin` (0.1-1.6 s, a full turn, the sweep at 0.92 s) and `axe_sweep` (0.6-1.35 s, the cut alone). Scythe and halberd sweeps, the chain-whip's circle, the Whirlwind art |
| Double_Blade_Spin | 91 | `sol_mod_anim_double_spin.glb` | the Arsenal: cut into `dspin` (0.2-1.9 s, a 1.9 m lunging flurry: right 0.45 / spin 0.85 / left 1.35 / right 1.55 s), `dspin_a` and `dspin_b` (its halves). Twin-stake chain hits 3-4 and heavy, the Crimson Flurry dash-through art |

The three Arsenal clips were bought in round 4 for 24 credits (one `3d_rigging` call each, 8 credits, on Sol's body
model at 1.88 m; jobs d0dbe736 / 8f9f079f / 564f667d). Every other Arsenal move re-cuts and re-times the clips above
(`game/scripts/items/arsenal_moves.gd` says which clip, window and speed each move uses). The build tool also adds
a `BladeL` socket in the left fist for the twin stakes.

The 11 MB rig downloads stay out of the repo; `game/tools/strip_rig_glb.gd <src> <dst> anim` makes the ~50 KB skeleton-only files.

## Not recommended
- **Generated video clips** (e.g. Seedance, about 35 credits for 5 s) only give a 2D video, which the game can't play on a character. Library clips are real motion capture data that drive the skeleton directly.
- **Clips with a shield** (Left_Slash shows one in its preview) have the free arm posed for a shield; on Sol that arm swings empty. They're usable, but the clips above suit a single sword better.
