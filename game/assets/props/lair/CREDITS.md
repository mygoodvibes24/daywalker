# Lair prop credits

These four models were generated on 2026-11-14 with Higgsfield, using Tripo text-to-3D
(`tripo_3d`; textured, PBR, standard quality). No reference images were used. Each GLB
ships with 2048 px colour, normal and ORM maps, which Godot imports VRAM-compressed at a
1024 px size limit. They dress the main-menu lair (`scripts/menu/lair_set.gd`).

| File | Face limit | Job ID |
| --- | --- | --- |
| `workbench.glb` | 16000 | 9e335ba1-d097-4c8a-a31a-3f8d1c42a5e8 |
| `blood_fridge.glb` | 14000 | c73cb030-ad6a-4b0c-9ba3-c0020d5a264f |
| `blade_rack.glb` | 16000 | 3717b1c0-0c6c-4fde-97fa-6a2d8427cd01 |
| `crossbow.glb` | 10000 | f2e8228c-80ea-436b-91b2-73dea05f9164 |

## Prompts

**workbench.glb**
- Prompt: heavy old wooden weapons workbench, thick scarred dark oak top, cast iron bench vice bolted on one end, a few tools, small oil cans and folded rags on the back edge, sturdy square legs with lower shelf, gothic dungeon workshop, realistic
- Negative: modern, plastic, cartoon

**blood_fridge.glb**
- Prompt: tall industrial medical blood bank refrigerator, double glass doors, steel frame, rows of red blood bags hanging on shelves inside, red interior light, realistic
- Negative: cartoon, household kitchen fridge
- Note: the doors came out opaque, so the set fakes the glass, interior light and bags in front of them.

**blade_rack.glb**
- Prompt: wall mounted dark wooden pegboard weapon rack, flat panel with rows of assorted daggers, long swords, machetes and sharpened wooden stakes hanging on pegs, gothic vampire hunter armory, realistic
- Negative: cartoon, guns

**crossbow.glb**
- Prompt: heavy wooden and steel hunting crossbow, dark wood stock, iron limbs, string drawn, lying flat, vampire hunter weapon, realistic, worn
- Negative: cartoon, toy, plastic
