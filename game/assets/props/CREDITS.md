# Street prop credits

All six models were generated on 2026-11-13 with Higgsfield, using Tripo
text-to-3D (`tripo_3d`; textured, PBR, standard quality). No reference images
were used. Each GLB ships with 2048 px colour, normal and ORM maps, which Godot
imports at a 1024 px size limit.

| File | Face limit | Job ID |
| --- | --- | --- |
| `sedan.glb` | 30000 | 6f0dfe9d-52f2-4bc8-8484-e9856dc914a9 |
| `dumpster.glb` | 12000 | ef79192c-ea96-4d57-b461-073939423ab7 |
| `street_lamp.glb` | 12000 | 18f572fd-f5b9-42ac-b247-01300a0a6e18 |
| `hydrant.glb` | 8000 | b257da2c-1118-4604-ba18-6c2a875dd2d7 |
| `news_box.glb` | 8000 | e3a9e10c-f4b2-42ff-a50a-3eca455e345b |
| `trash_pile.glb` | 10000 | 25cf5a2e-fcd2-4eb7-9579-91829b07efda |

## Prompts

**sedan.glb**
- Prompt: A realistic parked 1978 American four-door sedan, long boxy body, dark charcoal paint, dented fenders, rust spots, wet glossy surface, chrome bumpers, worn tires, grimy windows, no badges
- Negative: cartoon, toy, stylized, base, plinth, pedestal, ground plane, text, logos, badges, license plate text

**dumpster.glb**
- Prompt: A realistic rusted green commercial steel dumpster, rectangular waste container with two black plastic lids, sloped front, side lifting pockets, peeling paint, rust streaks, grime, dents, weathered
- Negative: cartoon, toy, stylized, base, plinth, pedestal, ground plane, text, logos, stickers

**street_lamp.glb**
- Prompt: A realistic ornate cast-iron Victorian street lamp post, tall slender fluted black iron pole with decorative scrollwork, single glass lantern head on top with glowing warm light, weathered, chipped black paint, rust
- Negative: cartoon, toy, stylized, plinth, pedestal, ground plane, square platform, text, logos, multiple lamps

**hydrant.glb**
- Prompt: A realistic weathered red cast-iron fire hydrant, classic American street hydrant with dome cap, side outlet nozzles and chains, faded chipped red paint, rust and grime
- Negative: cartoon, toy, stylized, base, plinth, pedestal, ground plane, sidewalk, text, logos

**news_box.glb**
- Prompt: A realistic battered metal newspaper vending box on four short legs, coin-operated street dispenser with hinged glass front door, faded blue paint, dents, scratches, rust, grime, blank unbranded panels
- Negative: cartoon, toy, stylized, base, plinth, pedestal, ground plane, text, logos, brand names, lettering

**trash_pile.glb**
- Prompt: A realistic pile of several bulging black plastic garbage bags heaped against an old weathered wooden slatted crate, wet glossy plastic, grimy, tied tops, street trash
- Negative: cartoon, toy, stylized, base, plinth, pedestal, ground plane, floor tile, text, logos

## Plaza set pieces (Undercroft entrance)

Two more models were generated on 2026-11-13 with Higgsfield, using Tripo
text-to-3D (textured, PBR). They are dense, so the game uses them only at the
cathedral plaza: one arch and two angels at the Undercroft entrance. Their
2048 px colour, normal and ORM maps are imported VRAM-compressed at a 1024 px
size limit. The job IDs were not recorded; the Tripo model IDs below are taken
from the node and texture names inside each GLB.

| File | Triangles | Tripo model ID |
| --- | --- | --- |
| `angel.glb` | 11396 | 18ceb336-f8b6-4c48-985f-7d6186d8bc21 |
| `gothic_arch.glb` | 19506 | 46061886-f36c-4244-b02b-5b40f81f55c1 |

**angel.glb**
- Prompt (summary; the exact text was not recorded): a weathered weeping-angel statue on a pedestal

**gothic_arch.glb**
- Prompt (summary; the exact text was not recorded): an ornate gothic stone arch with pinnacles over a stair entrance
