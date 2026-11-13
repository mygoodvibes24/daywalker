# Hollow Pack civilian (human form)

Original character, generated for Daywalker with Higgsfield on 2026-11-13.

- **civilian.glb**: Tripo text-to-3D (textured, PBR, standard quality, face limit 30000; job `77c01d85-9a6d-4d2d-8ccb-c7e31b97c968`), then Higgsfield auto-rig (job `2b6a40ed-7441-4141-920b-0b2602e95caa`, animation 16 RunFast, height 1.8 m).
- **civilian_rig.scn**: the same mesh and textures, re-skinned onto a 19-bone game skeleton by `game/tools/bake_rigs.gd`. This is what the game loads. The auto-rig's own skeleton and run clip do not line up with the mesh, so they are not used; the enemy is animated procedurally in `scripts/enemy.gd`.
- The `*_Color`, `*_NormalGL` and `*_ORM` images are the textures Godot extracted from the GLB.

## Prompt

> Full-body realistic 3D character, a rugged working-class dock worker man in his thirties, standing in a T-pose with arms straight out to the sides away from the body, legs slightly apart. He wears a worn tan brown canvas work jacket over a grey henley shirt, faded blue denim jeans, scuffed brown leather work boots. Short messy brown hair, stubble beard, weathered face. Grounded, photoreal, everyday realism. Empty hands, no props, no hat.

Negative prompt:

> cartoon, stylized, chibi, anime, base, plinth, pedestal, ground plane, weapon, tool, held object, fused limbs, arms attached to body, extra limbs, backpack, hat
