# Sol (Elijah "Sol" Marrow): hero model

- **Source:** generated with Higgsfield on 2026-11-13: Tripo text-to-3D (textured, PBR, ~45k face limit),
  then sent to Higgsfield's auto-rigger.
- **What ships:** `sol_unrigged.glb` (the textured text-to-3D mesh with its base color, normal and ORM maps)
  and `sol.scn`, built from it by `res://tools/build_sol_rig.gd`. The auto-rig output was not used: its skeleton
  was fitted to the wrong facing axis (arm joints at the sternum, knees at the coat hem) and it dropped the normal
  and ORM maps. The build script bakes the mesh to 1.88 m, feet at y=0, facing +Z, and adds a 20-bone skeleton
  (including three coat-panel bones) with procedural skin weights. All motion is procedural (`scripts/sol_anim.gd`).
- **Regenerate the rig:** `cd game && godot --headless -s res://tools/build_sol_rig.gd`

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
