# Map hero prop credits

All five models were generated on 2026-11-14 with Higgsfield, using Tripo
text-to-3D (`tripo_3d`, 5 credits each, 25 in total). No reference images were
used. Each GLB ships with colour, normal and ORM maps; Godot imports them with
web-safe "Lossy" compression (`compress/mode=1`) at a 1024 px size limit.

| File | Face limit | Triangles | Used for | Job ID |
| --- | --- | --- | --- | --- |
| `gantry_crane.glb` | 12000 | 10677 | the three quay cranes (34 m) | 3a68e495-2375-485e-a410-8ee6a2ad7032 |
| `shipping_container.glb` | 5000 | 4020 | loose containers on the apron (MultiMesh, 95 m range) | 57a24f6f-d77f-476e-bcae-0c10ba691985 |
| `trailer_home.glb` | 10000 | 8534 | the Hollow Pines trailer park (MultiMesh) | 9250b1ab-ee1b-4537-b37c-c6ece0f490b7 |
| `cypress_tree.glb` | 10000 | 9138 | hero cypresses round the plantation (MultiMesh, 140 m range) | 36fb89d9-9ce0-4c99-93e6-c946327483b5 |
| `plantation_facade.glb` | 15000 | 12728 | Belle Rive plantation ruin (bayou landmark) | 299e537a-d94e-4a1b-b411-4c6843cefd06 |

The container stacks, pines, bulk cypresses, warehouses, water tower, opera
house, cemetery and ship are procedural (scripts/map/*.gd).

## Prompts

- **gantry_crane.glb**: rusted harbour container gantry crane, tall steel A-frame legs on rails, long horizontal boom over water, red paint faded and rusty, industrial port crane, realistic game asset
- **shipping_container.glb**: rusted 40 foot steel shipping container, corrugated walls, closed cargo doors with locking bars, weathered dark red paint with rust streaks, realistic game asset
- **trailer_home.glb**: run-down 1970s single-wide trailer home, dirty white aluminium siding, small wooden porch with steps and railing, rusted roof, boarded window, realistic game asset
- **cypress_tree.glb**: bald cypress swamp tree with flared buttressed trunk base, gnarled branches draped with hanging spanish moss, louisiana bayou, realistic game asset
- **plantation_facade.glb**: ruined southern antebellum plantation house facade, tall white greek columns, two storeys, broken balcony railing, collapsed roof section, peeling paint, vines, realistic game asset

## Round 3 props (2026-11-18/19)
Tripo text-to-3D (standard, PBR), 5 credits each; normalised to face +Z on y=0 (see `r3_props_manifest.json`). Metallic-roughness and normal maps import at 512 px.

| File | Triangles | Used for | Job ID |
| --- | --- | --- | --- |
| `mausoleum.glb` | 15571 | eight family mausoleums either side of the cemetery cross avenue (one MultiMesh) | cc3ca11f-9910-4b0d-a61f-e2677f945645 |
| `gazebo.glb` | 16925 | a cast-iron gazebo on the Hollow Pines lake shore | 92b8c49e-17df-412c-9379-30504631c4b8 |
| `fishing_boat.glb` | 17236 | a wrecked skiff aground on the lake shelf | 1d8c858f-bff7-4f43-a510-2328c88f9806 |
| `street_clock.glb` | 14554 | post clocks on the cathedral plaza and the Palm Square | 43d91717-f9e0-4cd2-9de5-248d9dd4c2c4 |
