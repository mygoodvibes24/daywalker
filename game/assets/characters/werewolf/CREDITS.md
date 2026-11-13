# Hollow Pack werewolf (transformed)

Original character, generated for Daywalker with Higgsfield on 2026-11-13.

- **werewolf.glb**: Tripo text-to-3D (textured, PBR, standard quality, face limit 30000; job `61e6fcbd-6f76-4b9c-997d-f1da486d9607`), then Higgsfield auto-rig (job `c6b0eba2-1d51-4c6f-962a-96c066505905`, animation 512 Male_Head_Down_Charge, height 2.4 m).
- **werewolf_rig.scn**: the same mesh and textures, re-skinned onto a 19-bone game skeleton by `game/tools/bake_rigs.gd`. This is what the game loads. The auto-rig's own skeleton and run clip do not line up with the mesh, so they are not used; the enemy is animated procedurally in `scripts/enemy.gd`.
- The `*_Color`, `*_NormalGL` and `*_ORM` images are the textures Godot extracted from the GLB.

## Prompt

> Full-body realistic 3D creature, a huge hulking bipedal werewolf, half man half wolf, standing upright in a T-pose with long muscular arms held straight out to the sides away from the body. Matted shaggy brown and grey fur, wolf head with a long snarling muzzle and bared fangs, pointed ears, digitigrade wolf legs with clawed feet, large human-like hands with long black claws. Wearing torn, shredded work clothes: ripped dark work trousers torn off at the shins, remnants of a ripped flannel work shirt hanging from the shoulders. Grounded, photoreal, horror realism. Empty hands.

Negative prompt:

> cartoon, stylized, chibi, cute, anime, base, plinth, pedestal, ground plane, weapon, held object, fused limbs, arms attached to body, quadruped, tail fused to legs, extra limbs, armor
