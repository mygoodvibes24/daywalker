# Hollow Pack civilian (human form)

Original character, generated for Daywalker with Higgsfield on 2026-11-13.

- **civilian.glb**: Tripo text-to-3D (textured, PBR, standard quality, face limit 30000; job `77c01d85-9a6d-4d2d-8ccb-c7e31b97c968`), then Higgsfield auto-rig (job `2b6a40ed-7441-4141-920b-0b2602e95caa`, animation 16 RunFast, height 1.8 m).
- **civilian_rig.scn**: the same mesh and textures, re-skinned onto a 19-bone game skeleton by `game/tools/bake_rigs.gd`. It is now the fallback when the animated model is missing. The auto-rig's own skeleton and run clip do not line up with the mesh, so they are not used; the enemy is animated procedurally in `scripts/enemy.gd`.
- **rigged/civilian_rigged.glb**: the mesh turned to face +Z (feet at y=0, centred, 1.8 m), exported from Godot and auto-rigged again with Higgsfield (job `9c8b6921-45fe-4f23-a00c-1224e0c98119`, height 1.8 m, no animation) on 2026-11-14. This time the standard 24-bone humanoid skeleton fits the mesh. Its textures were stripped with `tools/strip_rig_glb.gd` because the build re-applies the original PBR material. The folder has a `.gdignore`, so Godot never imports it.
- **civilian_anim.scn**: built from that by `game/tools/build_enemy_anims.gd`, with the hero's seven clips (idle, run, sprint, attack, hit, death, jump; `assets/characters/clips/hero_clips.scn`) retargeted onto the skeleton. This is what the game loads.
- The `*_Color`, `*_NormalGL` and `*_ORM` images are the textures Godot extracted from the GLB.

## Prompt

> Full-body realistic 3D character, a rugged working-class dock worker man in his thirties, standing in a T-pose with arms straight out to the sides away from the body, legs slightly apart. He wears a worn tan brown canvas work jacket over a grey henley shirt, faded blue denim jeans, scuffed brown leather work boots. Short messy brown hair, stubble beard, weathered face. Grounded, photoreal, everyday realism. Empty hands, no props, no hat.

Negative prompt:

> cartoon, stylized, chibi, anime, base, plinth, pedestal, ground plane, weapon, tool, held object, fused limbs, arms attached to body, extra limbs, backpack, hat
