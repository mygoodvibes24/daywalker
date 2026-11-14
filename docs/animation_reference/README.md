# Sword Animation Reference

Preview clips of sword animations from the rig animation library that Higgsfield's auto-rigger (Meshy) uses. They're reference for how Sol's sword combat should move. The `.gif` files are the free previews; `sword_attacks_sheet.jpg` shows 8 frames of each side by side. These previews are the library's own reference renders (on a mannequin), kept here for study only; they don't ship in the game.

## Clips Sol already has (paid, in `game/assets/characters/sol/`)
| Clip | Library id | Used for |
|---|---|---|
| idle | 0 | standing |
| run | 14 | running |
| sprint (Lean_Forward_Sprint) | 509 | sprinting |
| slash (Left_Slash) | 97 | every combo hit; hit 2 plays it reversed |
| hit (Hit_Reaction) | 178 | taking damage |
| death (Dead) | 8 | dying |
| jump | 466 | airborne |

## Recommended next clips (8 credits each)
Each is a single `3d_rigging` call on Sol's already-uploaded, forward-facing body (same skeleton, so it drops straight into his clip set and the enemies' shared clips):
`model_url = https://d2ol7oe51mr4n9.cloudfront.net/user_3M3cbVYOpQkCAbZXwwBloXVahos/1cc3de5d-2289-444d-8383-29ffe7f0fd64.glb`, `height_meters = 1.88`, `enable_animation = true`, `animation_action_id = <id>`.

| Priority | Clip | Id | Role in combat |
|---|---|---|---|
| 1 | Triple_Combo_Attack | 105 | The 3-hit light combo (replaces the forward/reversed slash) |
| 2 | Thrust_Slash | 240 | Dash-in thrust / lunge attack |
| 3 | Charged_Slash | 242 | Heavy attack (hold attack) |
| 4 | Sword_Judgment | 102 | Finisher / execution on staggered enemies |
| 5 | Sword_Parry | 147 | Counter/parry window against the eye-flare telegraph |
| 6 | Weapon_Combo_2 | 241 | Alternate combo for heavier blades (cleaver family) |
| 7 | Combat_Stance | 89 | Combat idle when enemies are near |
| 8 | Right_Hand_Sword_Slash | 219 | Quick sprint attack |

Full set ≈ 64 credits. Clips 1–4 (≈ 32 credits) give the biggest improvement.

## Not recommended
- **Generated video clips** (e.g. Seedance, about 35 credits for 5 s) only give a 2D video, which the game can't play on a character. Library clips are real motion capture data that drive the skeleton directly.
- **Clips with a shield** (Left_Slash shows one in its preview) have the free arm posed for a shield; on Sol that arm swings empty. They're usable, but the clips above suit a single sword better.
