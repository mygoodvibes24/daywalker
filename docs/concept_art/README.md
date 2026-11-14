# Port Vesper — Concept Art & Art Direction

These paintings are the **build target**. Anyone building a level, prop, material or lighting setup works from the matching image here, not from guesswork. When the game and the art disagree, the art wins (unless gameplay requires otherwise, e.g. street widths for movement and pathfinding).

Generated with Higgsfield (GPT Image 2.6), 2026-11-13. Reference art only; not shipped in the game build.

## Global look (applies everywhere)
- **Palette:** blue-black night, warm amber practicals (gas lamps, windows, candles), crimson accents for vampire spaces, sodium orange for industry, cold moon-blue for werewolf spaces, sickly green for the bayou.
- **Always wet:** rain, puddles that mirror light sources, oil-sheen rainbows in gutters, steam from grates and vents.
- **Light sources are the composition:** every scene is lit by visible practical lights (lamps, windows, neon, candles) pooling on wet ground, with volumetric fog/haze around them. Large dark areas between pools.
- **Materials:** old brick, weathered limestone, wrought iron, wet cobblestone, rusted steel. Everything aged, stained and patched; nothing clean.
- **Sky:** heavy rain clouds, a visible moon breaking through, lightning on story beats.

## Locations

| # | Image | Location | Key elements to build |
|---|---|---|---|
| 01 | `01_plaza_night.jpg` | **Old Quarter cathedral plaza, night** (starting area) | Gothic cathedral with a glowing amber **rose window** and stained glass. A **sunken circular stairway** down to the Undercroft under an ornate **pointed gothic arch** with pinnacles, flanked by two **weeping-angel statues** on pedestals, stone balustrade around the pit, **red light rising from below**. Wet cobblestones (fan pattern), iron benches, a steam grate, lantern-style gas lamps on posts, French Quarter buildings with **wrought-iron galleries and hanging ferns** around the square. |
| 02 | `02_plaza_day.jpg` | **Same plaza, overcast day** | Flat silver light, wet stone, twin-spire cathedral facade, palm trees, 1970s sedans parked at the square's edge, pigeons. Faded pastel stucco (pink, cream) with green shutters. |
| 12 | `12_old_quarter_avenue.jpg` | **Old Quarter street** (most of the city) | 3-storey brick/stucco townhouses with **two levels of iron galleries** on thin columns over the sidewalk, ferns and wisteria, **lit shop windows** (antiques, hoodoo shop with candles and skulls, jazz bar with silhouettes), gas lamps, telephone poles with sagging wires, **cobbled crosswalks**, parked 70s cars, yellow hydrant, blue/red news boxes, trash cans and bags at the kerb, cathedral spires at the end of the avenue in fog. |
| 04 | `04_alley.jpg` | **Back alley** | Narrow brick canyon, rusted **zig-zag fire escapes**, caged bulb over a steel door, wall AC units and steam, green dumpsters, trash, torn posters, oily puddles, magenta neon and a spire glowing at the far end. |
| 03 | `03_velvet_mile.jpg` | **The Velvet Mile** (vampire district) | Art-deco/Beaux-Arts grand facades, **crimson-and-magenta neon**, a fan-shaped neon marquee over a club entrance, red velvet curtains, chandeliers seen inside, **brass stanchions and velvet ropes**, classical statues, palm trees, streetcar rails in the road, vintage black cars, banners on lamp posts, harbour with ships at the end. |
| 05 | `05_docks.jpg` | **The Docks** | Gantry cranes with red beacons, sodium floodlights, stacked rusted containers forming corridors, a corrugated warehouse whose open door reveals a **caged fight pit** and crowd, chain-link and razor wire, bollards and mooring rope along the quay, black water with oil sheen, a cargo ship. |
| 06 | `06_hollow_pines.jpg` | **Hollow Pines** (werewolf district) | Tall pines and fog, huge full moon, old trailers and porches with warm lights, **claw-torn chain-link**, muddy tyre tracks, log piles, rusted pickups. |
| 07 | `07_bayou.jpg` | **The Bayou** (final act) | Cypress trees with Spanish moss, black water, a **half-sunk plantation house** with columns, lanterns, fireflies, green-teal storm light, lightning. |
| 11 | `11_rooftops.jpg` | **Rooftops** (traversal layer) | Flat tar roofs at varied heights, wooden **water towers**, AC units, glowing skylights, gaps to leap, a red neon frame, spires and lightning on the skyline. |
| 08 | `08_undercroft.jpg` | **The Undercroft** (hub interior) | Flooded gothic crypt, ribbed vaults, **stepping stones across black water**, a planning table with maps and red evidence string, a **wall of blood fridges glowing red**, candles everywhere, angel statues on the stair, a gated **1890s subway tunnel** with rails, a crypt wall of carved names with candles. |
| 09 | `09_blood_den.jpg` | **Vampire blood den** (prologue) | Basement lounge under a club: red velvet booths, crystal chandeliers, gothic arches, IV blood bags, cages, chains on a pillar, a stair up to a strobing dance floor, haze. |
| 10 | `10_city_overview.jpg` | **City overview** | Map layout: cathedral square at the centre, Old Quarter grid around it, the neon Velvet Mile on one side, the port and cranes on the river, forest and swamp on the outskirts. |
| 13 | `13_main_menu_lair.jpg` | **Main menu: Sol's lair** (title-screen backdrop, built in `game/scripts/menu/lair_set.gd`) | Vaulted crypt basement with **wet, reflective stone floor**, a gated **subway tunnel** with rail lights on the left, Sol at a scarred **workbench** under a brass work lamp honing a silver blade on a whetstone (crossbow, stakes, knives, pistol, blood vials laid out), a **weapon pegboard** of swords and stakes, **blood fridges glowing red**, a map board/table with **red string**, iron candle chandelier and candle clusters, **Nia** standing at his shoulder with a tablet. The left third stays dark for the menu text. |

## How this maps to the current build
- The current playable map is the **Old Quarter around the cathedral plaza** (images 01, 02, 12, 04). That is the first thing to bring up to this standard.
- Gaps between the current build and the art, in priority order:
  1. **Undercroft entrance:** a sunken circular stair with a balustrade, ornate pointed arch with pinnacles, two angel statues, red uplight.
  2. **Cathedral:** a rose window with emissive stained glass, twin spires, portal statues and front steps.
  3. **Iron galleries:** two-level wrought-iron balconies on columns over the sidewalk, with hanging ferns, on most Old Quarter buildings.
  4. **Shopfronts:** lit, warm interiors visible through glass (antiques, hoodoo, jazz bar).
  5. **Cobblestone** fan-pattern paving in the plaza and cobbled crosswalks.
  6. **Gas-lantern lamps** (lantern head on a post, not a globe), with warm halos.
  7. **Weeping-angel statues** as a reusable prop (also in the Undercroft).
- Later districts and interiors (Velvet Mile, Docks, Hollow Pines, Bayou, Undercroft interior, blood den) each get built from their image when that part of the game is made.
