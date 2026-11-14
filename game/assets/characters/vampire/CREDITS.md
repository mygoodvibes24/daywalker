# Velvet Court vampire

Original character, generated for Daywalker with Higgsfield on 2026-11-13.

- **vampire.glb**: Tripo text-to-3D (textured, PBR, standard quality, face limit 30000; job `95bd8178-cdd0-4e59-8353-fd82f348734c`), then Higgsfield auto-rig (job `5e6a406c-34b8-4554-8cc9-c58986fc0c6a`, animation 509 Lean_Forward_Sprint, height 1.85 m).
- **vampire_rig.scn**: the same mesh and textures, re-skinned onto a 19-bone game skeleton by `game/tools/bake_rigs.gd`. It is now the fallback when the animated model is missing. The auto-rig's own skeleton and run clip do not line up with the mesh, so they are not used; the enemy is animated procedurally in `scripts/enemy.gd`.
- **rigged/vampire_rigged.glb**: the mesh turned to face +Z (feet at y=0, centred, 1.85 m), exported from Godot and auto-rigged again with Higgsfield (job `1c02dab3-dc30-4d6c-94f4-462f334b66cb`, height 1.85 m, no animation) on 2026-11-14. This time the standard 24-bone humanoid skeleton fits the mesh. Its textures were stripped with `tools/strip_rig_glb.gd` because the build re-applies the original PBR material. The folder has a `.gdignore`, so Godot never imports it.
- **vampire_anim.scn**: built from that by `game/tools/build_enemy_anims.gd`, with the hero's seven clips (idle, run, sprint, attack, hit, death, jump; `assets/characters/clips/hero_clips.scn`) retargeted onto the skeleton. This is what the game loads.
- The `*_Color`, `*_NormalGL` and `*_ORM` images are the textures Godot extracted from the GLB.

## Prompt

> Full-body realistic 3D character, a pale gaunt elegant aristocratic man, standing in a strict T-pose with arms straight out to the sides away from the body, legs slightly apart. He wears a dark charcoal-black tailored knee-length long coat with a tall upturned high collar and a deep crimson red silk lining visible at the lapels and coat edges, black waistcoat, dark trousers, polished black leather shoes. Slicked-back dark hair, sharp hollow cheekbones, sunken eyes with red irises, bloodless skin. Grounded, photoreal, period-modern noir style. Empty hands, no props.

Negative prompt:

> cartoon, stylized, chibi, anime, base, plinth, pedestal, ground plane, weapon, sword, cane, held object, fused limbs, arms attached to body, cape, wings, extra limbs
