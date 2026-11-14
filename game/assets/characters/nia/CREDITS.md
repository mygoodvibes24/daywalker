# Nia: Sol's assistant (main-menu set)

- **Source:** generated with Higgsfield on 2026-11-13. A full-body reference image was made with Higgsfield
  GPT Image (Nia standing, holding a tablet: glasses, hair in a bun, cream blouse, grey cardigan, dark
  trousers), then turned into a textured PBR mesh with Tripo H3.1 image-to-3D.
- **What ships:** `nia.glb` (the textured mesh with its base colour, normal and ORM maps, generated in her
  standing pose and unrigged) and `nia.scn`, baked from it by `res://tools/bake_nia.gd` (1.70 m tall, feet at
  y=0, facing +Z). The textures import VRAM-compressed with a 2048 px limit. Like the other characters, the
  `.glb` is excluded from the web export; only `nia.scn` and the textures ship.
- **Motion:** none in the asset. On the menu set `scripts/menu/nia_idle.gd` gives her a gentle sway, breathing
  and the occasional head tilt.
- **Rebake:** `cd game && godot --headless -s res://tools/bake_nia.gd`
