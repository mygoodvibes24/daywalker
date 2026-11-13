# Velvet Court vampire

Original character, generated for Daywalker with Higgsfield on 2026-11-13.

- **vampire.glb**: Tripo text-to-3D (textured, PBR, standard quality, face limit 30000; job `95bd8178-cdd0-4e59-8353-fd82f348734c`), then Higgsfield auto-rig (job `5e6a406c-34b8-4554-8cc9-c58986fc0c6a`, animation 509 Lean_Forward_Sprint, height 1.85 m).
- **vampire_rig.scn**: the same mesh and textures, re-skinned onto a 19-bone game skeleton by `game/tools/bake_rigs.gd`. This is what the game loads. The auto-rig's own skeleton and run clip do not line up with the mesh, so they are not used; the enemy is animated procedurally in `scripts/enemy.gd`.
- The `*_Color`, `*_NormalGL` and `*_ORM` images are the textures Godot extracted from the GLB.

## Prompt

> Full-body realistic 3D character, a pale gaunt elegant aristocratic man, standing in a strict T-pose with arms straight out to the sides away from the body, legs slightly apart. He wears a dark charcoal-black tailored knee-length long coat with a tall upturned high collar and a deep crimson red silk lining visible at the lapels and coat edges, black waistcoat, dark trousers, polished black leather shoes. Slicked-back dark hair, sharp hollow cheekbones, sunken eyes with red irises, bloodless skin. Grounded, photoreal, period-modern noir style. Empty hands, no props.

Negative prompt:

> cartoon, stylized, chibi, anime, base, plinth, pedestal, ground plane, weapon, sword, cane, held object, fused limbs, arms attached to body, cape, wings, extra limbs
