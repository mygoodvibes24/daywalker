# DAYWALKER: Blood and Moon — Critic Report, Round 2

Reviewed: commit `60fdb8f` (branch `claude/day-walker-game-concept-mz8vvv`, which includes the coat leg-contact fix and the staged round-3 assets), 2026-11-19.
Bar: **Elden Ring** for visuals, animation, combat feel, level design, audio and UI. A 10 means "stands next to Elden Ring"; a 5 means "a competent prototype with real assets".
No game code was changed. Screenshots: `/tmp/claude-0/-home-user-daywalker/dd1b8b5c-f35a-5096-ac5f-5ff9b687f52e/scratchpad/critic_r2/` (`native/`, `webshots/`, contact sheets `sheet_*.jpg`). Below, shots are named by file name only.

## Score table

| # | Category | R1 | R2 | Δ | One-line reason |
|---|---|---|---|---|---|
| 1 | Visuals | 5 | **5.5** | +0.5 | Real hills, pines, cypress and a matte coat lift the wilds, but the Velvet Mile and Docks are still grey boxes, the lake reads as a mud disc, the asphalt glitters and every boss fight is drowned in a red wash. |
| 2 | Characters and animation | 5 | **5.5** | +0.5 | The blade finally reads, the coat is black leather, the idle is calm and executions have a victim. The bosses are still stock enemy bodies under a lava-vein overlay in a shield bubble, and there is still no facial animation. |
| 3 | Combat and game feel | 5 | **6** | +1 | Strike-frame hits, an input buffer, move ramps, a camera sphere, lunges and leaps with health bars: the fundamentals are in. Telegraphs are MMO floor decals, the hit flash is a white silhouette, Frenzy is still a free buff and there is no lock-on. |
| 4 | Loop and level design | 6 | **6.5** | +0.5 | A shuffled 3-boss pool with the new Blood Knight, and districts that now have hills and a lake. There is still no in-run build choice, no traversal and no run modifier. |
| 5 | Audio | 6 | **6.5** | +0.5 | The silent bosses, Curfew, Descent and parry now have SFX. One combat track still covers every fight; the two boss themes are staged but not wired. |
| 6 | UI/UX | 4 | **6** | +2 | Touch controls, a phone layout, a bundled serif, a loading bar and fading hints. The night card sits on top of the map and the boss title, and the map is a flat schematic. |
| 7 | Story and presentation | 5 | **6** | +1 | A night flyover with case-file captions, a "why" on every night card and an epilogue give the Hunt a reason. Seraphine is still never on screen and bosses never speak to Sol before the fight. |
| 8 | Code quality | 6 | **6** | 0 | 161 smoke checks and clean data tables, but `city.gd` grew to 3,943 lines, nothing is typed, 6 MB of dead scenes still ship and the navmesh throws a sync error every load. |
| 9 | Web and performance | 3 | **5** | +2 | The Hunt now renders in the browser and is playable by touch. The `.pck` grew to 42 MB, and the busiest views cost 830–1,030 draws and 1.3–1.4M primitives, 3–4× a phone budget. |
| 10 | **Overall** | 5 | **6** | +1 | It has turned from a prototype into a playable browser game with a reason to play. Against Elden Ring it still looks like primitives and stock enemies in half the frames. |

### What got fixed since R1 (verified)
- **W1, the empty-sky Hunt in the browser: fixed.** In SwiftShader Chromium the Hunt draws the city, Sol and the HUD (`web_desktop_hunt_02_hunt_click.png`), and CI now guards it.
- **Touch, phone layout, the serif font, the loading bar and context hints (U1–U4): done.** The key hints now fade after 30 s (`hud.gd:_update_hints`).
- **Combat (G1–G5):**
  - Combo damage waits for the clip's strike frame (`player.gd:_attack`, `pending`).
  - There is a 0.2 s input buffer and 0.08 s / 0.12 s acceleration and stop ramps.
  - The camera casts a 0.3 m sphere.
  - Vampires lunge and changed wolves leap, each with a telegraph (`enemy.gd` `SPECIALS`).
  - Engaged enemies show health bars.
- **Blade and coat read (C2, V5): fixed.** The blade shows in idle and attacks (`sol_full_day.png`, `move_sprint_windup.png`), and the coat is matte black, no longer silver.
- **The execution victim reacts (C3).** The wolf is thrown back and lies dead (`move_exec_1..3.png`).
- **Bosses (C1, L1):**
  - The bosses play clips on `*_anim.scn` bodies.
  - Nights 1 and 2 draw from a pool of three, including the new Cassius Vane, Blood Knight.
  - The 3-boss win has a smoke check.
- **Audio (A1, A2, A4):** boss slam, swipe, bolt and blink SFX, the Curfew drone, the manhole clank, the land thud and the parry clang now exist and are hooked in.
- **Story (S1):** an intro (a night flyover with Nia, case-file captions and a letterbox), night cards and an epilogue.
- **Wilds (V1, V3, V4):**
  - Heightmap hills, a lake, a splat-shaded ground, real pines and cypress with impostors, undergrowth and trailers.
  - The white floating quad near the plaza is gone.

### Still open from R1
- **V2:** the tombs are still identical gabled boxes, now with a stone texture.
- **V6:** the shop windows are still flat cards with silhouettes.
- **V8:** the Docks are still a fence in front of boxes.
- **V9:** the plaza trees are still black cut-out cards.
- **C5:** there is still no lip-sync or blinks.
- **C7:** there are still only 3 enemy bodies.
- **C8:** Sol is still about 135k triangles.
- **G6:** Frenzy is still a pure buff, and even heals and halves incoming damage (`player.gd:414-416, 880`).
- **G7:** the parry is still on L3.
- **L3, L4:** no in-run perks and no traversal.
- **A3:** there is still one combat track.
- **A5:** bosses have no phase barks.
- **S2, S3:** no pre-fight exchanges, no Seraphine on screen, and no case files.
- **K1–K6:** the code debt items are all still open.
- **W2:** the draw-call budget is now worse.
- **W4:** the dead assets are still in the `.pck`.
- **W6:** the navmesh is still baked on load.

## How this was reviewed
- **Read:**
  - R1, `QUALITY_LOOP.md`, and the READMEs for the concept art (all 13 images), face scans and animation reference;
  - `game/assets_staging/README.md` and every manifest, plus their check sheets;
  - the key scripts (`player.gd`, `enemy.gd`, `hud.gd`, `hunt_director.gd`, `hunt_story.gd`, `boss_base.gd`, `blood_knight.gd`, `audio.gd`, `terrain.gd`, `build_sol_modular.gd`).
- **Native captures:** Compatibility renderer under xvfb at 1280×720, with a throwaway script (since deleted), Hunt seed 4242 and the director frozen for stills. They covered:
  - the 9 district views by night and by day, and aerial views of the terrain and the lake;
  - Sol close up (face, ¾, profile, neck, grip, front, back, day) and in motion (gameplay camera idle, run, sprint, stop);
  - every sword move (3 combo hits, charged, dash thrust, sprint slash, parry, execution in 6 frames);
  - the vampire lunge and the wolf leap, health bars and day people;
  - all 4 bosses (intro, portrait, attacks, gameplay camera);
  - the HUD, map, the Coat, the Vigil, a night card, the Curfew and pause;
  - the menu, hub, options, controls and the intro.
- **Web:** the release export (`index.pck` 41.99 MB, `index.wasm` 35.4 MB, 8.0 MB gzipped), served locally and driven by Playwright Chromium (SwiftShader, the CI launch args):
  - desktop 1280×720 with `?autohunt&debug` (the Hunt, walking, the map);
  - Pixel 7 in landscape with `?autohunt&debug` (the touch layer in play).

  Portrait was not re-shot: the round-2 UI group's `phone_portrait_rotate.png` shows the rotate prompt.
- **Forward+:** one plaza view, night and day, through lavapipe.
- **The staged assets** were judged from their check renders (`model_views_check.jpg`, `rigged_frames_check.jpg`, `contact_sheet.jpg`) and manifests, plus the Sol scan texture and the face-scan comparison sheets (`shots_facescan/compare_*.jpg`). The scanned head was not rebuilt into the rig, because that would change game assets.
- **Software rendering ran at about 1 fps,** so motion and timing are judged from code, frame sequences and R1 experience, not from feel at speed. **This report does not replace a real-GPU QA pass,** which is step 2 of the loop.
- **Boss shots:** in my boss stills Sol stood outside the arena, because `debug_skip_to("boss")` doesn't move him, so the frames are red-tinted. I used them for the portraits, and the round-2 group's in-arena captures (`sheet_r2d_bosses.jpg`) for the arena read.

### Probe numbers (native, Compatibility, 1280×720, gameplay camera unless noted)

| View | Draws | Primitives | Objects | R1 draws / prims |
|---|---|---|---|---|
| Old Quarter plaza, night / day | 538 / 519 | 999k / 994k | 1,285 / 988 | 710 / 829k |
| Old Quarter street, night / day | 596 / 587 | **1.09M / 1.05M** | 1,041 / 1,068 | 765 / 902k |
| Velvet Mile, night / day | 495 / 498 | 835k / 833k | 737 / 776 | 1,047 / 1.14M |
| Docks, night / day | 209 / 207 | 445k / 434k | 443 / 477 | 200 / 399k |
| Hollow Pines road, night / day | 288 / 282 | 627k / 623k | 1,095 / 1,061 | 274 / 487k |
| Lake shore, night / day | 264 / 253 | 540k / 540k | 1,020 / 731 | — |
| Trailer park, night / day | 233 / 230 | 529k / 527k | 661 / 694 | — |
| Bayou, night / day | 261 / 255 | 672k / 668k | 702 / 732 | 452 / 612k |
| Cemetery, night / day | 286 / 282 | 644k / 643k | 734 / 766 | 318 / 571k |
| Boss arena (Drowned Lawn), gameplay camera | **797–828** | **1.22–1.26M** | 1,114–1,617 | — |
| Deploy point (tank farm), the Curfew closing | 858 | **1.40M** | 1,110 | — |
| Map open over the world | **1,026** | 1.29M | 2,113 | — |

- **The Velvet Mile dropped from 1,047 to 495 draws** (prop merging works).
- **Triangles rose in every district,** by +100–200k. Terrain, trees and undergrowth added them, and the hero still costs about 135k.
- **The heaviest views are new places:** the boss arenas in the north and the tank-farm deploy, at 1.2–1.4M primitives.
- **Phone budget:** about 150–300 draws and 300–500k triangles. Every district except the Docks is over it on triangles, and the arenas are 3× over.

---

## 1. Visuals — 5.5 / 10 (R1: 5)

**What's good**
- **Hollow Pines by day** finally resembles `06_hollow_pines.jpg`: rolling hills, real tapered pines in depth, undergrowth, trailers with porches, chain-link (`dist_pines_day.png`, `dist_trailers_day.png`, `sheet_wilds1.jpg`).
- **The bayou cypress with hanging moss** reads as a swamp by day, and the night has fireflies and lanterns (`dist_bayou_*.png`).
- **The night Old Quarter** is still the best look: wet street, lit shopfronts, iron galleries, parked sedans (`dist_quarter_st_night.png`).
- **The plaza at night** now frames the cathedral, its rose window and the Undercroft arch well (`dist_plaza_night.png`).
- **The red Curfew band on the horizon** is a strong, readable silhouette from every district.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| V1 | High | `wet_materials.gd` (asphalt and road normal/roughness), `terrain.gd` splat | Every road reads as **glittering gravel**: white per-pixel sparkles across the asphalt, by day and by night (`dist_velvet_day.png`, `dist_quarter_st_night.png`, `move_*.png`). Near the tank farm the ground is a stretched, glossy, blobby normal map like molten plastic (`ui_hud_explore.png`, `ui_curfew.png`, `web_desktop_hunt_03_walk.png`). | Clamp the wet-specular noise: roughness ≥0.25 on asphalt, a normal strength of about 0.3, and mip-biased or filtered sparkle. Fix the tank-farm splat tiling (UV scale ×4–8, normal strength ≤0.5). Swap in staged `cracked_asphalt_*` and `weathered_concrete_*`. | S | 0 |
| V2 | High | `map/velvet.gd`, `city.gd` (Art Deco blocks) | `dist_velvet_day.png`, `dist_velvet_night.png`: plain grey towers with unlit white-square windows. There's no fan marquee, palm or neon in frame, and a big maroon slab stands on the median. That's nothing like `03_velvet_mile.jpg`. | Put cornices, setbacks, vertical neon strips and lit marquee canopies on the first two floors. Turn the window grid down to warm, sparse windows. Make sure the palms render (check the trunk-only black pole in frame). Swap the maroon banner slab for thin banner cards on the lamps. | M | 0 (optional: 1 marquee model, 5) |
| V3 | High | `map/docks.gd`, `player.gd` spring | `dist_docks_*.png`: the shot is a black fence in front of untextured container boxes. The camera sits outside the fence because the fence isn't on the spring's collision layer. | Texture the containers with staged `rusted_metal_*` and paint them in 4–5 colours with ribs. Add sodium floods, bollards, a quay edge and water. Put the fence on layer 1, or fade it within 2 m of the camera. | M | 0 |
| V4 | High | `map/terrain.gd` (lake) | `dist_lake_day.png`, `air_lake_*.png`: the lake reads as a **flat brown disc**, with no sky reflection, no shoreline foam or reeds, and no darker deep water. | Give the water a material: dark albedo, roughness 0.05, a fresnel sky tint, scrolling ripple normals and a depth-faded shore band. Add a reed or cattail card ring and 2 rowboats (staged `fishing_boat`). | S–M | 0 |
| V5 | Med | `atmosphere.gd` (boss and Curfew tint), `hunt_fx.gd` | The whole boss fight is a **saturated red wash**: sky, ground and Sol are all crimson (`sheet_r2d_bosses.jpg`, `boss_*_portrait.png`). Elden Ring arenas keep their colour; the threat comes from the boss. | Tint only the sky, fog and wall (fog colour ×0.4 red). Keep the ground and characters in natural night light. Save the full-screen red for low HP or outside the Curfew. | S | 0 |
| V6 | Med | `city.gd` plaza trees | `dist_plaza_day.png`: the plaza's trees are still flat black cut-outs, now very visible by day (R1 V9). | Use the cypress or pine impostor pipeline from `trees.gd`, or a live-oak card with the staged moss card. | S | 0 |
| V7 | Med | `map/cemetery.gd` | `dist_cemetery_*.png`: dozens of identical gabled boxes in a grid (R1 V2, half done: a stone texture and crosses). | Mix in the staged **mausoleum** (one per row end, ≤12 instances, LOD) and vary the box tombs in height, lid and colour. Add puddles and cast-iron fences between rows. | S–M | 0 (staged) |
| V8 | Med | Night exposure in the wilds | `dist_pines_night.png`, `dist_lake_night.png`: Sol and the ground are near-black. Moonlight is too weak for the forest to read. | Raise moonlight energy ×1.5 in `pines` and `bayou`, add a cool moon rim on Sol, and use ground fog that catches the moon. | S | 0 |
| V9 | Low | Shopfronts (R1 V6) | `move_*.png`: the orange window cards with black silhouettes dominate every Quarter fight. | Fake interior depth with an interior-mapping shader, and use silhouettes in only 1 window in 6. | M | 0 |
| V11 | Med | `terrain.gd` ground splat, north wilds | `air_north_day.png`, `air_bayou_day.png`: from above, the north is sparse trees on a uniform beige-grey floor, washed out by fog. There are no paths, clearings, rocks, fallen logs or colour breaks, and the bayou's moss cards read as palms from above. | Add splat variety: staged `forest_floor`, `mud` and `mossy_rock`, a dark wet band along the roads and the lake, and needle drifts under the pines. Scatter rocks and fallen logs (MultiMesh). Thin the day fog 30% in the north. | M | 0 |
| V10 | Low | Lamp halos | `dist_quarter_st_night.png`: a beige halo disc is drawn **on** the shop window at right, as a billboard sorted wrong. | Depth-test the halo quads, or fade them when occluded. | S | 0 |

## 2. Characters and animation — 5.5 / 10 (R1: 5)

**What's good**
- **The coat is now matte black leather** and reads as the concept, close up and in daylight (`sheet_sol1.jpg`, `sol_full_day.png`).
- **The blade is visible** in idle and during attacks, without the white disc (`sol_full_day.png`, `move_sprint_windup.png`).
- **The calm Idle_02** looks grounded, and the stance with enemies near holds the sword low and to the side (`dist_bayou_night.png`).
- **The execution is a real two-person beat** now: the wolf staggers, takes the strike, is thrown and lies dead (`move_exec_0..3.png`).
- **Combo hits 1–3, the charged slash and the sprint slash** read as real mocap swordplay (`sheet_moves1.jpg`, `sheet_moves2.jpg`).

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| C1 | High | `hunt/bosses/*.gd`, `boss_base.gd` | All 4 bosses are stock bodies (vampire ×1.55, werewolf, civilian) covered by the same **lava-crackle vein overlay**, inside a translucent pink **shield bubble** (`boss_*_portrait.png`, `sheet_r2d_bosses.jpg`). Marcus is still a street vampire. Elden Ring's bar is a unique silhouette, scale and move set per boss. | **Wire the staged assets** (see "Staged assets" below): Marcus Crane (his own mesh plus 3 clips), the Abomination (a 2.8 m mesh plus slam, grab-throw and roar), and the Alpha (werewolf ×1.35 plus the new heavy swipe, pounce and roar). Drop the vein overlay on Marcus, and keep it subtle and emissive on the Abomination. Show the bubble only during the intro's invulnerability. | L | 0 (staged) |
| C2 | High | `assets/characters/sol/*` neck, `build_sol_modular.gd` | `crop_face.png`, `sol_face_day.png`: under the chin a **vertical orange-peach smear** of stretched texture runs down the throat. The collar is low-poly, with jagged shards (`sheet_sol1.jpg`). | Re-project or paint the neck with the face's skin tone. Push the neck verts under the collar, as was done for the scan head. Add a collar ring of 300–600 tris or smooth the coat collar normals. | S–M | 0 |
| C3 | Med | Boots and coat hem | `crop_feet.png`: the boots render **pale grey like socks**, and a beige band (lining or a backface) shows at the coat hem. | Darken the boot albedo (or use a separate boot material at about 0.06 albedo, roughness 0.45), and make the coat inside the same dark material (cull disabled, back-face albedo ×0.3). | S | 0 |
| C4 | Med | Faces | There are still no blinks and no jaw or lip movement on Sol or Nia while they talk in the menu, the intro and the hub (R1 C5). | Add a jaw flap driven by voice amplitude (spectrum analyser on the Voice bus) and random blinks via a lid blendshape or eyelid bone scale. About 40 lines per character. | M | 0 |
| C5 | Med | Enemy specials (`enemy.gd:_start_special`) | The vampire lunge is the slash clip **slowed to 0.45×**, and the wolf leap is the **jump clip slowed to 0.55×** (`enemy_vampire_lunge_windup.png`, `enemy_wolf_leap_*.png`). They read as slow motion, not intent. | Use the staged `vampire_anim_lunge` (trim to 1.6 s, strike at 0.77 s) and `werewolf_anim_pounce` (take-off 0.6 s, land 1.3 s, strip the 4.7 m root motion and drive the arc in code). | M | 0 (staged) |
| C6 | Med | Enemy roster | There are still 3 bodies. The elites are the same body with a fresnel bubble (R1 C7). | Retexture variants cheaply: tint and accessory swaps for the Courtier and Thrall. Longer term, one new model each. | M | Optional 13–26 |
| C7 | Low | Hit flash (`enemy.gd:861`) | `move_dash_windup.png`: an enemy hit turns the whole body **flat white**, a cheap mobile-game read. | Use a 60 ms additive rim plus a blood spray at the contact point and a short hit-stop instead of a full-white overlay. | S | 0 |
| C8 | Low | Sol's triangles | About 135k for the hero (R1 C8), and the hidden second sword mesh still ships. | Decimate the body and coat for the web tier and delete the spare sword. | S | 0 |

**The scanned head: verdict.** Do **not** switch it on as is. The face chart itself is good: it is sharp, has the right identity and reads better than the stylised head (`sol_scan_head_albedo.jpg`, left half). Four things block it:
1. **A hole under the nose:** the nostrils and philtrum are a black and brown smear in the face chart (the albedo at about 360–600, 700–760).
2. **A shredded side atlas:** hair, ears and neck are hundreds of tiny islands, with skin-coloured confetti inside the hair. That makes the temple and ear seams and the blotches in `compare_compat.jpg` (row 2: forehead, temple and cheek blotches).
3. **A dark neck:** a dark ring under the jaw (`compare_neck.jpg`, combo3).
4. **Ghosted lips and cheeks,** because only ±30° views exist.

Switch it on after this cleanup pass, all in `tools/project_face_texture.py` and `build_sol_modular.gd`:
- (a) Inpaint the nostril and philtrum region from `s01_front.jpg` (OpenCV Telea over a hand mask).
- (b) Re-chart the hair, ears and neck as 3–4 large xatlas charts. Flood-fill hair texels with a hair tone (from the median of hair-mask pixels) instead of the nearest photo.
- (c) Feather the face chart 8–12 px into the side atlas, with Poisson blending on the border.
- (d) Tone-match the under-jaw neck to the cheeks, and push it under the collar.
- (e) Re-capture the ±30° views (0.5–1 credit, as the staging README notes).
- (f) Gate it on an A/B contact sheet in menu lamp light, daylight and the gameplay camera.

Effort M; credits about 1. Do the same pipeline on Nia only after Sol's cleanup proves out.

## 3. Combat and game feel — 6 / 10 (R1: 5)

**What's good**
- **The combo lands on the strike frame,** with a 0.2 s buffer. Moves are data in `sol_moves.gd` (hit time, lunge, cooldown, lock).
- **Two attacks per enemy** with dodgeable windows (a 0.55 s lunge wind-up, a 0.5 s leap wind-up plus 0.6 s in the air). A hit breaks the special (`enemy.gd:893`).
- **Engaged enemies have health bars,** and a red orb plus an "[E] BITE" prompt mark the bite window (`move_exec_2.png`).
- **Movement ramps and the sphere-cast camera** stop the instant start and stop and the trunk clipping.
- **The execution has camera pull-in, invulnerability and a victim.**

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| G1 | High | `hunt_fx.gd` `line_telegraph` / `circle_telegraph`, used by `enemy.gd` and the bosses | `move_charged_windup.png`, `sheet_r2d_bosses.jpg`: attacks are announced by **flat salmon-pink floor rectangles and rings**. That's MMO raid language. Elden Ring telegraphs through the body (wind-up pose, a glint, sound), so reading the enemy is the skill. | Drop the floor decals on common enemies. Keep a very faint one only on boss AOEs. Telegraph with the staged clips' wind-ups (heavy swipe arms rise at 0.9–1.3 s), a red eye glint, and a hiss or roar cue 0.3 s before the strike (staged `sfx_vampire_hiss` and `sfx_werewolf_roar`). | S | 0 |
| G2 | High | `player.gd` | **No lock-on.** Soft-lock picks the nearest enemy within 5 m. With 2–4 enemies and a boss there is no way to commit to one target or strafe around it. That is a core Elden Ring verb. | Add a lock-on toggle (R3 / middle mouse / a touch button): the camera frames Sol and the target, movement strafes while locked, and the target switches with the right stick or mouse flick. Show a small reticle. | M | 0 |
| G3 | Med | `player.gd:414-416, 863-880` | **Frenzy is still a pure buff**, and stronger than in R1: ×2 damage, +3 HP/s regen and half damage taken, for 8 s (R1 G6). | Frenzy should cost: no parry or bite, attacks auto-target the nearest living thing (civilians too), HP drains 2/s instead of regenerating, and a 25% damage-taken increase. | S | 0 |
| G4 | Med | No stamina or commitment | Attacks, dashes (3 charges) and parries have only cooldowns. There's no resource tension, so mashing is optimal. | Use a light stamina bar (or tie dash charges to attacks): heavy and charged attacks and dashes cost, and running out slows recovery. Show it as a thin bar under Blood. | M | 0 |
| G5 | Med | Camera occluders | `sol_gamecam_idle.png`, `move_gamecam_combo.png`, `dist_trailers_day.png`: lamp posts and trunks fill the middle of the frame, in front of Sol, because the sphere stops clipping but not occlusion. | Dither-fade (alpha hash) any mesh between the camera and Sol within 6 m. Posts and trunks need a "camera_fade" material flag. | S–M | 0 |
| G6 | Med | Boss move sets | The bosses differ mostly by numbers. The Knight's set is dash, slam, swipe×2 and a bolt ring (`blood_knight.gd`), and the others mirror it (`_choose_attack`). There are no delayed attacks, grabs or combos with mix-ups. | Give each boss one signature: Marcus's afterimage blink-feint combo (the staged slash combo, 4 hits, with a delayed 4th); the Abomination's grab-throw (staged); the Alpha's pounce plus a roar that summons. Add one delayed-swing variant per boss to punish panic dodges. | M | 0 |
| G7 | Low | Hit stop and impact | The shots show no blood spray at the contact point, and enemies slide back without a hit-react pose on light hits. | Add a blood spurt (GPUParticles, 12 quads) at the blade-body contact, a 40–60 ms hit-stop on the victim only, and the `hit` clip on light hits. | S | 0 |
| G8 | Low | Parry on L3 (R1 G7) | Still an awkward pad binding. | Put the parry on LB, move quick-use to the D-pad, and add a rebind option. | S | 0 |

## 4. Loop and level design — 6.5 / 10 (R1: 6)

**What's good**
- **A shuffled night pool** (Alpha, Marcus, Knight) with the Abomination fixed on the Final Night. The arenas shuffle per seed, and each night card says why tonight's boss hunts you.
- **The north is now a landscape:** a ridge, the Hollow bowl round the arena, a pine-ringed lake you can wade, trailer park, logging yard and water tower (`air_*`, `sheet_wilds1.jpg`).
- **The 3-boss win is proven end to end** in the smoke test.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| L1 | High | `progression.gd`, `hunt_director.gd:_on_boss_died` | There is **no in-run build choice** beyond chapel ranks of small stat bumps (R1 L3). Nightreign's loop lives on "pick 1 of 3" relics and weapon finds. | Add a Blood Rite after every boss and landmark: choose 1 of 3 strong perks (for example, the dash leaves a bleeding afterimage, parry heals, the bite chains to a second target). Add 4–6 build-defining Vows. | M | 0 |
| L2 | High | Districts | The Docks (`dist_docks_*`) and the Velvet Mile (`dist_velvet_*`) are long flat streets of boxes, with no verticality and no secrets. The Quarter has no rooftops (`11_rooftops.jpg`). | Add 2–3 micro-POIs per district with a reward: a container-top cache reached by stacked crates, a club basement (`09_blood_den.jpg` in miniature), a crypt under the mausoleum, a rooftop chain with a water tower. | M | 0 |
| L3 | Med | Traversal (R1 L4) | No vault or climb. At 13 m/s Sol crosses a 480 m map with nothing to do between sites. | Add a sprint-vault onto ledges up to 1.2 m, and a "blood leap" (dash plus jump, 8 m) for roof gaps. Add rooftops to 2 Quarter blocks. | M–L | 0 |
| L4 | Med | Run variety | Sites never change type by day, and there is no run modifier. | Add a seeded Hunt modifier per run (Blood Moon: +elites; Fog: shorter view, more stragglers; Sun-starved: no sun heal). Change 1–2 site types on Day 2. | S–M | 0 |
| L5 | Low | `debug_skip_to("boss")` | It doesn't move Sol to the arena (my boss stills, `sheet_boss_*.jpg`). That's test-only, but QA screenshots hit it too. | Teleport Sol to `arena.pos + 6 m` in `debug_skip_to` when the target is boss or final. | S | 0 |

## 5. Audio — 6.5 / 10 (R1: 6)

**What's good**
- **The missing SFX now exist and are hooked in:**
  - boss slam, swipe, bolt and blink;
  - the Curfew drone;
  - manhole and landing sounds timed to each Descent type (`hunt_director.gd:_deploy_sfx`);
  - the parry clang.
- **120 voice files** with subtitles. The contradicting lines were re-keyed (A4).
- **Two boss themes are staged:** Marcus's velvet-jazz menace and the Abomination's taiko-and-choir piece. Each is about 45–50 s and loops.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| A1 | High | `audio.gd:set_boss`, `hunt_config.gd` | **One `combat.ogg` covers every fight and every boss** (R1 A3). Elden Ring boss music is half the event. | Add a `music` key per boss def, and have `set_boss(on, track)` crossfade to it: `music_boss_marcus.ogg` and `music_boss_abomination.ogg` from staging. The Alpha and the Knight need two more themes (2 × 3.2 credits), or reuse the Abomination's at −3 semitones with no choir for the Alpha. Listen first: the manifest says they haven't been checked by ear. | S | 0 (staged), +6.4 for 2 more themes |
| A2 | Med | `audio.gd` enemy barks | Enemies have no voice beyond a hiss and growl. The staged hiss, roar, claw swipe, lunge whoosh, pounce whoosh, body fall and slam aren't wired. | Hook them to the new clips' events: the roar at 0.97 s in `werewolf_anim_roar`, the whoosh at the lunge release, the body fall at `ground_impact`. Pitch the Alpha's down 3 semitones. | S | 0 (staged) |
| A3 | Med | `dialogue.json` | The bosses have no phase-change lines. The Knight uses `court_taunt_3` as his intro and has no death line (`hunt_config.gd`). | Add 8 lines: an intro, a phase change and a death for Cassius, and a phase change for each of the other 3 bosses. | S | 2 |
| A4 | Low | Mix | The swing and hit SFX are 2 variants each, so they repeat over a 3-hit combo. | Make 4 variants each with ±8% pitch randomisation, and a heavier hit layer on charged and execution. | S | 2 |

## 6. UI/UX — 6 / 10 (R1: 4)

**What's good**
- **The touch layer** (`ui/touch_controls.gd`, 252 lines): a stick, look drag, attack/hold, dash, jump, bite, parry, sprint, map, the Coat and pause. It shows only on touch.
- **The Coat and the Vigil screens** are clean, serif and dark, and are the closest thing to an Elden Ring menu in the game (`ui_inventory.png`, `ui_levelup.png`).
- **The web shell** has a progress bar, and the bundled Cormorant Garamond now shows in the browser too.
- **The hints are context-only** and fade after 30 s.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| U1 | High | `hunt_story.gd` (layer 35), `map_screen.gd`, `hud.gd` announce | **The night card draws over the map** (`web_desktop_hunt_04_map.png`). It also stacks with the "DAY 1 / The Curfew falls at dusk" announcement and the `?debug` text (`web_desktop_hunt_02_hunt_click.png`, `dist_pines_night.png`), and with the boss title, the big announce and the key hints at the boss intro (`sheet_r2d_bosses.jpg`). Three text layers fight in the same 40% of the screen. | One message queue for the night card, announcements and the boss title: never two at once. Hide the card when any menu opens (layer below the map, or `visible=false` while `main.menu_open()`). Move the announcement to the top third, and the boss name to the bottom, Elden Ring style. | S | 0 |
| U2 | Med | `hud.gd` / `hunt_hud.gd` | The HUD is **text-heavy**: BLOOD, HUNGER, DAYWALKER, DASH 3/3, RANK 1, TITHE 0, REVIVES, plus three counters on the right and a compass with 10 icons. Elden Ring shows three bars, a small rune count and items. | Use bars without labels (Blood red, Hunger purple, Dash as 3 pips), and put the Tithe and Rank in the bottom-right like runes. Show the right-side counters only on the map or pause screen. Keep at most 5 compass icons (the nearest per type). | M | 0 |
| U3 | Med | `ui/map_screen.gd` | `ui_map.png`: flat rectangles and coloured districts. The lake, terrain, roads and arenas aren't drawn (the Hollow Pines area is plain blue), and "THE BAYO…" is clipped. | Bake a top-down render of the world into a paper-toned map texture at build time (an orthographic camera at 1 px = 0.5 m, through a sepia ink shader), with icons on top. Fix the label clipping. | M | 0 |
| U4 | Med | `touch_controls.gd`, `hud.gd`, `hunt_story.gd` on phone | `web_phone_hunt_02_hunt_tap.png` (Pixel 7, landscape): the touch layer shows and is well labelled (STRIKE, DASH, PARRY, BITE, RUN, JUMP, COAT, MAP, pause). But the night card and "DAY 1 / The Curfew falls at dusk" cover about 60% of the screen. The **virtual stick sits on top of the night card**, and HUD text is about 2× too large for the screen. Two oversized white lamp-halo discs hang in the middle of the view. | On phones: a 0.8 UI scale for the HUD text, cards at most 35% width in the top-left, the announce at 60% size, and nothing under the stick zone (left 30%, bottom 55%). Clamp the halo billboard size in pixels on the web tier. | S–M | 0 |
| U5 | Low | Enemy health bars (`enemy.gd:_build_bar`) | A thin **white** bar floats over every engaged enemy (`enemy_bars_gamecam.png`). It reads as debug. | Make them dark-red bars with a dark outline, shown only after the first hit, fading 3 s after the last. The boss bar is fine. | S | 0 |
| U7 | Med | `hunt/hub_panel.gd` | `menu_hub.png`: the hub is still a dense two-column text form over a blurred lair (R1 U5). Nia, who "has the coat brushed and the blades oiled", isn't part of it. | Frame the hub camera on Nia at the map table. Show the armoury as cards with the charm icons over the weapon rack. Play `hunt_hub` when it opens. | M | 0 |
| U8 | Low | `ui/results_screen.gd` | `ui_results_win.png`: a good serif panel, but the stats switch to a sans font mid-panel, and the HUD stays visible behind it. | Use one type family for the stats (Cormorant small caps), and hide the HUD while the results show. | S | 0 |
| U6 | Low | Intro and night card timing | The night card stays up for the first 10+ s of play and covers the left third of the screen (`dist_*_night.png`). | Show it for 4 s, then collapse it to a one-line objective under the compass. | S | 0 |

## 7. Story and presentation — 6 / 10 (R1: 5)

**What's good**
- **The intro:**
  - a letterboxed night flyover of the real city with Nia's briefing;
  - case-file captions ("CASE FILE · THE UNDERCROFT");
  - a title card: "PORT VESPER, LOUISIANA · THE NIGHT THE ACCORD BROKE".
- **Every night card gives the hunt a motive** ("Wren's husband was found with a bite in his throat…").
- **The results screen carries an epilogue,** with an epitaph per killer boss ("DAWN OVER PORT VESPER", `ui_results_win.png`).
- **The menu lair is still the best-composed screen in the game** (`menu_title.png`): the chandelier, string board, Sol at the bench and Nia, close to `13_main_menu_lair.jpg`.
- **The flyover exposes the city's weak side:** from above it is a dark grid of boxes with lit windows (`intro_02..05.png`). The captions carry the scene, not the image.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| S1 | High | Bosses | **No boss ever speaks to Sol before the fight,** and the Knight has no voice at all. Elden Ring's best bosses get a line and a pose before the bar appears. | Add a 4–6 s pre-fight beat: the camera cuts to the boss (using the staged roar or idle), a 1-line taunt, a Sol reply, then the bar. Wire it through `hunt_director._spawn_boss` with `intro_t`. | M | 1.5 (6 lines) |
| S2 | Med | Seraphine | She is never seen (R1 S2). The Final Night is "her Abomination" with no face behind it. | Show her on a rooftop over the Final arena (a Nia-pipeline model, or a silhouette card with red eyes), plus 2 voiced lines. | M | 12.5 (model) + 0.5, or 0 with a silhouette |
| S3 | Med | Meta | Wins add nothing to the story (R1 S3). | Unlock a case file per boss kill in the hub: a one-page text with a portrait and a 20 s voice log. | S | 1.5 |
| S4 | Low | Intro stills | The intro is captions over gameplay renders. The concept art is reference-only. | Use 3–4 painted stills (from the concept art style) under the case-file captions for the Accord's backstory. | S | 1.25 |

## 8. Code quality — 6 / 10 (R1: 6)

**What's good**
- **161 smoke checks,** covering terrain, the coat's rest state, moves, execution reactions, the 3-boss win, story cards and touch flags.
- **Data-first design:** `SPECIALS`, `NIGHT_BOSS_POOL`, `sol_moves.gd`, `map_layout.gd`.
- **CI** guards the web render, web-safe textures and the culling setting.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| K1 | Med | `city.gd` 3,943 lines, `lair_set.gd` 1,361, `build_sol_modular.gd` 1,763 | Grew since R1 (it was 3,918). | Split as in R1 K1: `city/textures.gd`, `materials.gd`, `batcher.gd`, `map/quarter.gd`, `props_place.gd`. | M | 0 |
| K2 | Med | Whole codebase | 0 `class_name`, 28 untyped `var main`/`var director`, 154 `.get()`/`has_method` calls (131 in R1). | Add `class_name` to Main, Player, Enemy, HuntDirector, BossBase and Poi, and type the cross-script fields. Start with the files round 3 touches anyway (enemy, bosses). | M | 0 |
| K3 | Med | Navmesh | Every load logs `Navigation map synchronization error … merge a navigation mesh polygon edge` (web console and native log), plus the `agent_radius is ceiled` warning. | Match `cell_size` between the NavigationMesh and the map (`navigation/3d/default_cell_size`), round `agent_radius` to a multiple of the cell size, and check for overlapping terrain and city source geometry at the plate edge. | S | 0 |
| K4 | Low | Dead weight | `assets/characters/sol/sol.scn` (1.46 MB), `sol_anim.gd`, `player.gd:_build_model`, and the `*_rig.scn` fallbacks (4.64 MB) still ship. | Delete them: the bosses now use `*_anim.scn`. | S | 0 |
| K5 | Low | Boss debug path | `debug_skip_to("boss")` leaves Sol outside the arena (L5). | See L5. | S | 0 |

## 9. Web and performance — 5 / 10 (R1: 3)

**What's good**
- **The Hunt renders in the browser** (`web_desktop_hunt_02_hunt_click.png`): the city, Sol, the HUD, the map. It was ready after about 108 s under SwiftShader.
- **There are no script errors** in the console, only the navmesh error.
- **Touch and phone layout:** see below.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| W1 | High | Triangles and draws (probe table) | 1.0–1.1M primitives in the Quarter. 1.22–1.4M and about 800–860 draws at the boss arenas and the tank-farm deploy. Map open: 1,026 draws. Phone budget: about 300 draws, 500k tris. | (1) Distance-cull the undergrowth and grass at 25–35 m on the web tier. (2) Impostors for pines beyond 40 m (they exist; start them earlier on web). (3) Terrain LOD: halve the far chunks. (4) Hero LOD: Sol 135k down to about 40k on web. (5) Freeze or hide the 3D world while the map or the Coat is open (`map_screen.open` → `main.process_mode` plus a `camera.cull_mask` of 0). Target ≤350 draws and ≤600k tris everywhere. | M | 0 |
| W2 | High | Download | `index.pck` **42.0 MB** (40.9 MB gzipped; it was 38.2 MB in R1), plus 8.0 MB of wasm. Dead weight: `sol.scn` 1.46 MB, `*_rig.scn` 4.64 MB, scan-head textures shipped while unused (about 0.8 MB). The staged assets will add about 15–20 MB if imported as delivered. | Delete the dead assets (K4). Downscale the staged boss textures to 1024 px and the prop textures to 512 px. Use mono 96 kbps for music. Decimate Marcus (48.7k) and the Abomination (38.2k) to about 20k each. Target ≤40 MB after integration. | S–M | 0 |
| W3 | Med | Phone (Pixel 7 emulation, SwiftShader) | The Hunt was ready after 135 s; the desktop took 108 s. It renders and the touch layer works (`web_phone_hunt_02_hunt_tap.png`). On a real mid phone, the 800+ draw and 1.2M+ primitive views will be well under 30 fps. There is no "lite" tier yet. | Add a Lite quality preset, auto-picked on touch devices: no rain, no undergrowth, a 60 m draw distance, shadows off, a 0.75 render scale, no post FX. | S | 0 |
| W5 | Info | Forward+ (native, lavapipe) | `fwd/dist_plaza_night.png`: Forward+ adds visible fog glow and bloom round the lamps and the rose window, which is a real mood step up. It also costs **1,842 draws and 2.43M primitives** on the plaza (it was 538 / 1.0M on Compatibility). | For a future native desktop build, give the Forward+ tier its own LOD and shadow budget. | — | — |
| W4 | Low | Load path | The navmesh is still baked on load (R1 W6), and the bake also throws K3's error. | Bake at import into a `.res`, or per district over several frames. | M | 0 |

---

## Staged assets: how to use them in round 3

`game/assets_staging/` (63 MB on disk, 185.65 of 195 credits) is good and well-documented. The check renders show usable meshes and clips. None of it is wired yet, and as delivered it would add triangles and megabytes the web build can't afford. Integrate in this order:

1. **Creature clips (largest feel gain, no new meshes).** Add the clips to `tools/build_enemy_anims.gd` so they bake into `werewolf_anim.scn` and `vampire_anim.scn` (they share each enemy's skeleton).
   - **Werewolf:**
     - `heavy_swipe`: a parryable heavy, strike at 1.57 s; make it the wolf's second normal attack.
     - `pounce`: replaces the slowed jump clip in the leap. Strip the 4.7 m root motion and drive the arc in code, taking off at 0.6 s and landing at 1.3 s.
     - `roar`: on aggro and the Alpha's phase change, with the SFX at 0.97 s.
     - `run_feral`: chase locomotion. Drop the hips z travel so it loops in place at about 7 m/s.
     - `death_heavy`: on executions and big kills. Check the sign of the 1.44 m slide.
   - **Vampire:**
     - `lunge`: replaces the slowed slash. Trim to 1.6 s; strike at 0.77 s.
     - `claw_combo`: cut into a 2-hit string (0.57 / 1.3 s) for elites; strip the 1.5 m advance or use it as a lunge.
     - `backflip`: an evade after a parried or blocked hit, with 2–3 m backward displacement in code and i-frames from 0.6 to 1.4 s.
   - **Check before wiring:** several clips leave frame in the check render (`ww_run`, `ww_pounce`, `vp_claw_combo`, `mc_combo`), so their root motion must be stripped as the build tool already does for Sol's combo.
2. **Bosses.** Read the `rigged/` GLBs with GLTFDocument, as `build_enemy_anims.gd` does for the enemies, re-apply the PBR material from the textured GLB, and bake `marcus_anim.scn` and `abomination_anim.scn`. Teach `boss_base.add_rig` a `model` key so a boss def can name its own body.
   - **Marcus Crane** (1.88 m, 48.7k tris):
     - Decimate to about 20k for the web, and force metallic 0 and roughness 0.75 on the velvet, as the manifest notes.
     - He has **no idle, run or hit clip:** retarget the vampire's idle, run and hit by bone name. It's the same 24-bone Meshy rig, but check the rest-pose difference on the arms.
     - Map the clips: `slash_combo` (hits 0.83 / 1.13 / 1.63 / 2.5 s) is his signature 4-hit string with a delayed last hit; `dash_lunge` is the gap closer (re-aim the diagonal root motion onto his facing); `death` plays at 0 HP.
     - **Remove the vein overlay and the shield bubble on him.** The crimson-lined coat is his silhouette.
   - **The Abomination** (2.8 m, 38.2k tris):
     - Decimate to about 20k, and give the veins an emissive mask from the albedo's red channel (in place of the overlay).
     - It has **no locomotion:** retarget the werewolf's `run_feral` at 0.8× speed.
     - Map the clips: `slam` (strike 1.67 s, wind-up peak 0.37 s) is the arena slam; `grab_throw` is the new unblockable grab (a dodge test); `roar` is the intro and the phase-2 summon.
   - **The Hollow Alpha:** the werewolf body ×1.35 with the new werewolf clips at 0.85× playback, darker fur and stronger eye glow, and the roar pitched down 3 semitones. It costs no download.
3. **Audio.** Add a `music` key to each boss def and crossfade to it in `audio.gd:set_boss`. Wire the 7 creature SFX to the clip events above. **Listen to both themes first:** they haven't been checked by ear, and the choir may sing words.
4. **Textures** (18 tiling sets plus 2 alpha cards at 1024 px). These directly fix V1, V3, V6 and V7:
   - `cracked_asphalt` and `weathered_concrete` for the roads and the tank farm (with tuned specular);
   - `rusted_metal` for the containers;
   - `wet_cobblestone` for the plaza fan;
   - `brick`, `stucco` and `limestone` for the Quarter, replacing the procedural `_stone_textures()` where it reads flat;
   - `slate_roof` and `tar_roof_gravel` for the roofs;
   - `bark_pine` and `bark_cypress` for the trunks, and `forest_floor`, `mud` and `wet_sand` for the terrain splat;
   - `moss_card` for cypress moss and the plaza oaks, and `pine_branch_card` for close pine LOD;
   - `cemetery_marble` for the tombs.

   Import as Lossy WebP (already set), and use 512 px on the web tier for anything not under the hero's feet.
5. **Props** (15.5–17k tris each, about 1 MB each):
   - the **mausoleum** in the cemetery and the Hollow Pines graveyard, at most 12 instances, with LOD;
   - the **gazebo** in the Velvet Mile Palm Square, or the plaza (one per map);
   - the **fishing boat** on the bayou and lake shore (V4);
   - the **street clock** at Quarter intersections (2–3 per map).

   Generate LODs (the importer does), merge them per chunk with `city.gd`'s batcher, and give each a box collider from the manifest's `collision` hint.
6. **Nia's face scan:** hold it until Sol's scanned head passes the cleanup in §2. Then run the same pipeline with her draft `scan.json`, after measuring `eyes_px` properly.

**Budget after integration:** keep the `.pck` at ≤40 MB (requires K4 and texture downscales) and the arenas at ≤600k tris (requires the decimation).

---

## Round 3 fix plan

Five parallel groups with non-overlapping file ownership. Items are ordered by expected score gain per effort. A shared file is owned by exactly one group; the others ask its owner.

### Already in flight (two round-3 agents were running when this report was written)
- **The asset-integration agent = Group A.** It is wiring the creature clips, the Marcus and Abomination models, Nia's face, the textures, the props, and the boss themes and SFX.
  - Not yet covered by it, and still needed: A5 (the boss pre-fight beat), the decimation of Marcus and the Abomination for the web, and removing the vein overlay and bubble on Marcus.
  - **Nia's face:** I recommend holding it until Sol's scan-head cleanup passes (§2 verdict). If it is wired now, apply the same cleanup steps (a)–(d) to her charts before it ships.
  - **Textures and props:** placing them touches Group C's files (`city.gd`, `map/*.gd`). Only one of the two agents should edit those files, so the coordinator must sequence them.
- **The QA round 2 bug agent covers part of Groups B and D:**
  - camera blockers = **B6 / G5**;
  - SPECIALS timing = part of **B1 / C5**;
  - the night card = **D1 / U1 / U6**;
  - boss parry, fall recovery, the intro Esc, hub shop scrolling, the Options layout and the charged slash are QA functional bugs not scored here.
  - **Still open after it,** B: lock-on, Frenzy cost and stamina, the neck/boots/hit-flash pass, the scanned-head cleanup. D: the HUD diet, the parchment map, boss music switching, case files. **All of C and E** (world art and budget, loop and code health) are untouched by either agent and are the next two agents to start.

### Group A — Asset integration (agent 1)
Files: `game/assets_staging/*` (moving files out), `game/assets/characters/{marcus,abomination,werewolf,vampire}/*`, `tools/build_enemy_anims.gd`, `scripts/hunt/bosses/*.gd` (including `boss_base.gd`), `scripts/hunt/hunt_config.gd` (boss defs: `model`, `music`), `assets/audio/music/*`, `assets/audio/sfx/*` (new files), `assets/props/map/*` (new props), `assets/textures/*` (new folder), `tests/smoke_test.gd` (boss, clip and prop checks).
1. **Creature clips into the enemy anim scenes,** with root motion stripped. Give `enemy.gd`'s owner (Group B) the clip names and strike times. *(Characters +0.5, Combat +0.25.)*
2. **Marcus and the Abomination as real bodies,** decimated, with retargeted locomotion, no vein overlay on Marcus and emissive veins on the Abomination; the Alpha on the new werewolf clips at ×1.35. *(Characters +1, Visuals +0.25.)*
3. **Boss music per boss** (after listening) and creature SFX files. Group B places the SFX calls in `enemy.gd`; the boss scripts get them here. *(Audio +0.5.)*
4. **Textures and props** moved to their final folders with web-tier sizes. Group C places them in the world. *(Visuals +0.5, via C.)*
5. **Boss pre-fight beat** (S1) in `boss_base.gd`, using the intro_t window and the roar or idle clip. Voice lines come from Group D. *(Story +0.5.)*

### Group B — Combat feel and Sol (agent 2)
Files: `scripts/player.gd`, `scripts/enemy.gd`, `scripts/sol_moves.gd`, `scripts/sol_modular_anim.gd`, `scripts/hunt/hunt_fx.gd` (telegraphs), `scripts/fx.gd`, `tools/build_sol_modular.gd`, `tools/project_face_texture.py`, `assets/characters/sol/*`, `docs/face_scans/*`.
1. **G1: body-language telegraphs** instead of floor decals on common enemies, wired to the new clips from A1. *(Combat +0.5.)*
2. **G2: lock-on** (pad, mouse and touch button; the touch layout is coordinated with Group D). *(Combat +0.5.)*
3. **G3: Frenzy with a real cost, and G4 a light stamina.** *(Combat +0.25.)*
4. **C2 + C3: Sol's neck smear, collar, boots and coat hem; C7: hit flash into a rim, plus blood spray (G7).** *(Characters +0.5.)*
5. **The scanned head cleanup** (§2 verdict a–f), then switch `USE_SCANNED_HEAD` on if the A/B passes. *(Characters +0.5.)*
6. **G5: dither-fade for occluders between the camera and Sol.** *(Combat +0.25, Visuals +0.25.)*

### Group C — World art and frame budget (agent 3)
Files: `scripts/city.gd` (and any split of it, K1), `scripts/map/*.gd` (`velvet`, `docks`, `cemetery`, `wilds`, `trees`, `terrain`), `scripts/wet_materials.gd`, `scripts/atmosphere.gd`, `scripts/props.gd`, `scripts/hunt/poi_dressing.gd`, `project.godot` (LOD and culling settings only).
1. **V1: glitter asphalt and the tank-farm ground** (staged asphalt and concrete). *(Visuals +0.5.)*
2. **W1: the web-tier triangle and draw budget:** undergrowth cull, earlier impostors, terrain LOD, hiding the world behind the map. *(Web +1.)*
3. **V2 + V3: the Velvet Mile facades and neon, the Docks containers, quay and fence layer.** *(Visuals +0.5, Loop +0.25.)*
4. **V4 + V7 + V6: the lake water, the mausoleum mix in the cemetery, the plaza trees.** *(Visuals +0.5.)*
5. **V5 + V8: no red wash in the arenas, readable moonlight in the wilds.** *(Visuals +0.25.)*
6. **K1: split `city.gd`** while it's open anyway (no behaviour change; the smoke test guards it). *(Code +0.5.)*

### Group D — UI, story, audio and web shell (agent 4)
Files: `scripts/hud.gd`, `scripts/ui/*` (including `touch_controls.gd` and `map_screen.gd`), `scripts/hunt/hunt_story.gd`, `scripts/hunt/hunt_hud.gd`, `scripts/audio/audio.gd`, `scripts/audio/dialogue.gd`, `data/dialogue.json`, `assets/audio/voice/*`, `docs/DIALOGUE.md`, `game/web/shell.html`, `export_presets.cfg`, `.github/*`.
1. **U1: one message queue** (night card, announcements, boss title); the night card hides under menus. *(UI +0.5.)*
2. **U2 + U5: an Elden-Ring-lean HUD** (bars without labels, runes bottom-right, fewer compass icons, dark-red enemy bars). *(UI +0.5.)*
3. **U3: a baked parchment map.** *(UI +0.25, Loop +0.25.)*
4. **A1 (the `audio.gd` side):** `set_boss(on, track)`, the crossfade and a final-night layer. **A3:** boss phase lines plus Cassius's intro and death, and the pre-fight lines for A5. *(Audio +0.5, Story +0.25.)*
5. **S3 case files in the hub; S2 Seraphine as a rooftop silhouette with 2 lines.** *(Story +0.5.)*
6. **W2 (shell side):** cache the `.pck` with a service worker, so a second visit doesn't download 42 MB. *(Web +0.25.)*

### Group E — Loop, code health and download (agent 5)
Files: `scripts/main.gd`, `scripts/hunt/hunt_director.gd`, `scripts/hunt/poi*.gd`, `scripts/hunt/deploy.gd`, `scripts/progression.gd`, `scripts/inventory.gd`, `scripts/loot.gd`, `scripts/items/*`, `scripts/settings.gd`, dead assets (`assets/characters/sol/sol.scn`, `*_rig.scn`, `scripts/sol_anim.gd`).
1. **L1: the Blood Rite pick-1-of-3 after bosses and landmarks,** plus 4–6 build-defining Vows. *(Loop +0.5.)*
2. **K4 + W2: delete the dead scenes and scripts** (about 6 MB off the `.pck`); **K3: fix the navmesh cell-size sync error;** **W4: bake the navmesh at import.** *(Web +0.5, Code +0.25.)*
3. **L4: a seeded Hunt modifier per run,** and site types that change on Day 2. *(Loop +0.25.)*
4. **L2: micro-POIs** (container-top cache, club basement, crypt) as POI types; Group C builds the dressing geometry. *(Loop +0.25.)*
5. **K2: `class_name` plus typed `main` and `director`,** starting with main, hunt_director and poi. *(Code +0.5.)*
6. **L5: `debug_skip_to("boss")` teleports Sol into the arena.** *(QA quality.)*

**Credit budget for round 3:** 0 required. Optional extras:
- 2 more boss themes, 6.4;
- 14 voice lines, about 3.5;
- the ±30° Sol re-capture, 1;
- a Seraphine model, 12.5.

**Expected after round 3, if the groups land:** Visuals 6.5, Characters 6.5–7, Combat 7, Loop 7, Audio 7.5, UI 7, Story 6.5–7, Code 7, Web 6.5, Overall 7.

---

## Ceiling vs Elden Ring

Elden Ring is a AAA native title: hand-authored worlds, about 200 bespoke bosses, a performance-captured cast and an orchestral score. This project is Godot 4.3 on the WebGL2 Compatibility renderer, with AI meshes, library mocap, AI voices, single-threaded wasm and a phone target. The honest ceilings:

| Category | Realistic max with this stack | What stops it | What would raise it |
|---|---|---|---|
| Visuals | **7** (7.5 native Forward+) | No GI, volumetrics or SSR on WebGL2, a weak shadow budget, a phone triangle budget, AI textures with baked light. | A desktop Forward+ build with volumetric fog and SDFGI. An artist pass on the 3 hero districts. Hand-placed lighting per POI. |
| Characters and animation | **7** | AI topology, no facial rig, library clips only. Paired animations are faked from two separate clips. | The scanned-head pipeline on all hero faces, plus ARKit blendshapes from a phone capture. A paid mocap session for 10 bespoke boss moves. |
| Combat and feel | **8.5** | Nothing structural: tuning, VFX, sound, camera and lock-on. The limit is library coverage for bespoke boss moves. | Lock-on, stamina and posture, plus per-boss signature moves (the staged clips cover about half). |
| Loop and level design | **8** | Hand-made content per district and team time. | Rooftop traversal, interiors and more POI types. |
| Audio | **8** | AI voices lack an actor's range in big scenes; AI music lacks orchestral authorship. | A real composer for 2 boss themes, and actors for Sol and Nia. |
| UI/UX | **8.5–9** | Nothing technical. | — |
| Story and presentation | **6.5–7** | No facial performance means no cinematic scenes. | In-engine boss beats, Seraphine on screen, voiced case files. |
| Code | **9** | Nothing. | The refactors and typing above. |
| Web and performance | **7.5** | A 40 MB download and single-threaded WebGL2 cap phones. | A lite tier, streaming districts, a service-worker cache. |
| **Overall** | **about 7.5** | The browser and AI-asset stack. "Elden Ring" fidelity is not reachable in a phone browser. | The same project exported as a native desktop build is worth about +0.5 on Visuals and Overall. |

**For the owner:** the realistic target is "a tight, moody browser action-roguelite with Elden-Ring-style combat language", not Elden Ring fidelity. Combat, UI, loop and code can get within 1.5 points of the bar. Visuals, characters and story stop around 7 on this stack, whatever the effort.
