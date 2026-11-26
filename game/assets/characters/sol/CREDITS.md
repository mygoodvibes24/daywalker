# Sol (Elijah "Sol" Marrow): hero model

- **Source:** generated with Higgsfield on 2026-11-13: Tripo text-to-3D (textured, PBR, ~45k face limit),
  then sent to Higgsfield's auto-rigger.
- **Retired (round 3):** the first in-game Sol, `sol.scn` built from `sol_unrigged.glb` by `tools/build_sol_rig.gd` and
  animated procedurally by `scripts/sol_anim.gd`, was replaced by the modular, clip-driven `sol_modular.scn`
  (`tools/build_sol_modular.gd`). The old mesh, its textures, the build tool and the animator were deleted to cut
  about 1.6 MB from the web download; they are in git history (before round 3) if they are ever needed.

## Prompt

> Full-body realistic 3D character, standing in a symmetrical A-pose with arms held away from the body, empty open
> hands. A tall, lean, wiry Black man in his early 30s with shoulder-length dreadlocks (locs), calm serious face,
> small dark round sunglasses. He wears a long black leather trenchcoat reaching below the knees, open at the front
> with a clear gap between the coat and the legs, over a black fitted shirt, dark slim trousers and black leather
> boots. Realistic, grounded, cinematic game character, detailed PBR textures, proportional anatomy, feet flat on
> the ground.

Negative prompt:

> weapon, sword, blade, knife, gun, held object, cartoon, anime, chibi, stylized, toy, big head, base, plinth,
> pedestal, stand, ground plane, coat fused with legs, merged legs, skirt, cape, extra limbs, hat, helmet

# Sol, modular hero (`sol_modular.scn`, the one the game uses)

- **Source:** every part generated with Higgsfield on 2026-11-13 (Tripo multiview / image-to-3D, PBR maps)
  from turnaround images of the reference design: the coatless body (henley, harness, cargo trousers,
  boots), the long open leather trenchcoat, a head-and-neck bust, a right fist in a sword grip, a combat boot,
  and four swords (silver blade, sabre, cleaver, rapier). The body was turned to face +Z and sent to the Meshy
  auto-rigger (24-bone humanoid) with seven clips: idle, run, sprint, slash, hit, death, jump; later eight
  sword clips on the same rig (Triple_Combo_Attack, Thrust_Slash, Charged_Slash, Sword_Judgment, Sword_Parry,
  Weapon_Combo_2, Combat_Stance, Right_Hand_Sword_Slash; see docs/animation_reference/README.md). On
  2026-11-18 Idle_02 (library id 11, same rig) was added as Sol's standing idle (`sol_mod_anim_idle02.glb`);
  the rig's original look-around idle is kept only as a long-idle fidget (`idle_look`).
  On 2026-11-26 Casual_Walk_inplace (library id 613, same body, 8 credits) was added as the walk
  (`sol_mod_anim_walk.glb`).
- **What ships:** `sol_modular.scn` and the four `sol_sword_*.scn` scenes, plus the extracted texture maps
  (`sol_mod_*_Color/NormalGL/ORM_*`; VRAM compressed, 2048 px max for body, head and coat, 1024 px for the hands
  and swords). The runtime loads nothing else: the `.glb` files are build sources and are excluded from exports.
- **Build sources in the repo:** `sol_mod_rig_idle.glb` (the rigged body + idle, textures stripped),
  `sol_mod_anim_*.glb` (one clip each, skeleton only, ~50 KB), `sol_mod_body_src.glb` (the body's full-res
  maps), `sol_mod_coat_src.glb`, `sol_mod_head_src.glb`, `sol_mod_hand_src.glb`, `sol_mod_sword_*.glb`.
  The seven full 11 MB rig downloads and the unused boot model are not committed (they stayed in the build
  machine's scratch folder; `tools/strip_rig_glb.gd` makes the small versions from them).
- **Rebuild:** `cd game && godot --headless -s res://tools/build_sol_modular.gd` (about 25 s). The tool rescales
  the centimetre rig to metres, cuts the body's head, hands and ponytail away, fits the bust, fists (mirrored
  for the left), procedural round sunglasses and the sword, swings the coat's sleeves onto the arms, keeps the
  coat outside the body, skins the coat (upper half: weights sampled from the body under it, sharpened with a
  nearest-bone falloff; skirt: 12 spring-bone chains x 5 links, leather and lining sharing weights) and gathers the clips (root
  motion stripped into a "travel" value, combos cut into moves with their strike times). Each sword scene gets a
  GripPoint marker, computed from its grip (the narrow stretch under the guard), that weapon_visual.gd puts
  on the fist's grip socket (fitted to the tunnel of the curled fingers).
- **Motion:** clips blended by `scripts/sol_modular_anim.gd`; the coat skirt is simulated by
  `scripts/coat_sim.gd`. The boots are the body's own: the separate boot model did not add enough to justify
  a second texture set and an ankle seam.

# Sol's scanned head (`sol_scan_head*`, used by `sol_modular.scn`)

- **Source:** a simulated face scan (docs/face_scans/README.md). Ten capture photos and two skin plates were
  generated with Higgsfield (GPT Image 2.6); four of them were reconstructed with Tripo H3.1 multiview-to-3D
  (`sol_scan_head_raw.glb`, a build source). `tools/project_face_texture.py` projects the photos onto the
  decimated head and bakes the maps: `sol_scan_head.glb` (36k triangles, skeleton space),
  `sol_scan_head_albedo.jpg` (2048 x 1328), `_normal.png` and `_orm.png` (1024), `_detail_normal.png` and
  `_detail_mask.png` (512), and `_eyes.json` (eye positions for the eyeballs). All Lossy (WebP) imports.
- The older Tripo bust (`sol_mod_head_src.glb`) is kept as the fallback (`USE_SCANNED_HEAD = false`).
