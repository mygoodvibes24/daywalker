# DAYWALKER: Blood and Moon — Critic Report, Round 1

Reviewed: commit `8c3fb2a` (branch `claude/day-walker-game-concept-mz8vvv`), 2026-11-15.
Reviewer role: tough, fair game critic and technical reviewer. No game code was changed.

## Score table

| # | Category | Score | One-line reason |
|---|---|---|---|
| 1 | Visuals | **5 / 10** | The night Old Quarter and the Velvet Mile have real mood; the pines, cemetery, camps and trailers are still grey primitive boxes and cylinders, and Sol's coat renders silver. |
| 2 | Characters and animation | **5 / 10** | Good AI-built heads for Sol and Nia, and the sword moves are real mocap. But the coat looks metallic, the blade barely reads, the bosses are rescaled stock enemies, and there is no facial animation. |
| 3 | Combat and game feel | **5 / 10** | The tools are there: a data-driven move set, parry, hit-stop and attack tokens. Light hits land before the swing does, enemies have one attack each, and the execution has no victim reaction. |
| 4 | Nightreign loop and level design | **6 / 10** | The whole loop exists and works: hub, edge deploy, 21 sites, Curfew, 3 bosses, results, meta currency. The districts outside the Quarter are empty, and runs barely vary. |
| 5 | Audio and dialogue | **6 / 10** | 57 voiced lines, 3 music beds and 23 SFX, with subtitles. The bosses, the Curfew, the parry and the Descent make no sound of their own, and several lines contradict the game. |
| 6 | UI/UX | **4 / 10** | KB/M and pad are complete and the map is clear. There are no touch controls, the phone layout is broken, the web build loses the serif font, and the HUD shows stale key hints. |
| 7 | Story and presentation | **5 / 10** | The bible is still strong and the menu banter is charming. In the game there is no intro, no cutscene and no reason given for the Hunt. |
| 8 | Code quality and architecture | **6 / 10** | Clear data tables and a 138-check smoke test that passes in 1.5 min. But `city.gd` has 3,918 lines, nothing is typed between scripts, and dead fallbacks still ship. |
| 9 | Web and performance | **3 / 10** | In headless Chromium the Hunt shows only an empty sky on both desktop and Pixel 7, which must be confirmed on a real GPU. The download is 73 MB, the city costs 700–1,050 draw calls, and there are no touch controls. |
| 10 | **Overall** | **5 / 10** | Huge progress since round 0 (4/10): it is now a real game structure with real assets. Yet the main channel (the browser) may not show the world at all, and the art outside two districts is still blockout. |

Round 0 scores for comparison: Game Feel 4, Visuals 3, Story 7, Code 5, Web 6, Overall 4.

### What got fixed since round 0
- **All round-0 critical and high bugs are fixed.** Curbs no longer stop Sol (sidewalks are visual only). Enemies path on a baked navmesh (13,345 polys, about 0.9–1.5 s to bake natively). Slow-motion effects are tracked separately. Strikes lock their direction at wind-up and can be sidestepped.
- **The game has art.** Sol is modular (body, head, hands, sword, and a 12×5 spring-bone coat). Nia, the vampire, the werewolf and the civilian are AI-generated, rigged and clip-animated. The props are generated PBR models (lamps, cars, angel, arch, crane, plantation and more).
- **Audio exists.** There are voiced lines, music that changes with context, SFX and subtitles.
- **A Nightreign-style Hunt replaced the sandbox.** It also adds a lair main menu with Sol and Nia, a hub with Sunmarks, a pause menu, options and a controls screen.
- **The tests are real.** The smoke test went from a few checks to 138, and they cover the Hunt.
- **Still open from round 0:**
  - phone layout and touch (round-0 bug 12);
  - Frenzy has no downside (round-0 bug 9);
  - the "Until Dawn vs. this toolchain" question. This report answers it in the Ceiling section.

## How this was reviewed
- **Read:** the README, the story bible, the round-0 report, the concept art (all 13), the animation reference, `DIALOGUE.md`, and the key scripts. The scripts were `main.gd`, `player.gd`, `sol_moves.gd`, `sol_modular_anim.gd`, `coat_sim.gd`, `enemy.gd`, `hunt/*`, the bosses, `map/map_layout.gd`, `city.gd` (structure), `audio/*`, `menu/*`, `ui/*`, `settings.gd`, `atmosphere.gd` and the smoke test.
- **Smoke test:** `--headless -s res://tests/smoke_test.gd`. Result: **PASS**, 138 checks, 1 min 35 s. The log has 3,846 lines of `ERROR: Parameter "m" is null` from the headless dummy renderer.
- **Native captures:** Compatibility renderer under xvfb at 1280×720, with throwaway scripts (since deleted). They covered the menu, the hub, options, controls, Sol and Nia close-ups, every district by night and by day, Sol in close-up, sprinting and running, every sword move, the Descent, a camp at idle and in a fight, and the Night-1 boss intro.
- **Probes:** draw calls and primitives per district (`RenderingServer.get_rendering_info`), navmesh bake time, camp idle and aggro, and a parse of the `.pck` file table.
- **Web:**
  - The release export served locally and driven by Playwright Chromium (SwiftShader, about 1 fps), at 1280×720 and with Pixel 7 emulation.
  - Run each time: menu, hub, Begin the Hunt, the Hunt, walking, the map.
- **Not verified this round:**
  - a full 3-boss win through to results (a probe was cut short). The smoke test does cover death after boss 1 through to results.
  - the Curfew damage probe in my own run (the smoke test checks it and passes).
  - the inventory, level-up and Curfew screenshots.
  - a Forward+ capture.
  These are listed as "verify" items, not as deductions.
- **Screenshots:** `/tmp/claude-0/-home-user-daywalker/dd1b8b5c-f35a-5096-ac5f-5ff9b687f52e/scratchpad/critic_r1/`. Below they are named by file name only. The contact sheets are `sheet_*.png`.

### Probe numbers

| View (native, Compatibility, 1280×720) | Draw calls | Primitives | Objects |
|---|---|---|---|
| Main menu (lair) | 716 | 513k | 910 |
| Old Quarter plaza, night / day | 710 / 667 | 829k / 824k | 1,230 / 1,160 |
| Old Quarter street, night / day | 765 / 724 | 902k / 901k | 1,284 / 1,217 |
| Velvet Mile, night / day | **1,047 / 1,017** | **1.14M / 1.13M** | 1,257 / 1,510 |
| Docks, night / day | 200 / 182 | 399k / 389k | 400 / 675 |
| Hollow Pines, night / day | 274 / 230 | 487k / 476k | 467 / 659 |
| Bayou, night / day | 452 / 398 | 612k / 600k | 660 / 827 |
| Cemetery, night / day | 318 / 288 | 571k / 571k | 514 / 717 |

- **Rough mobile budget** for WebGL2 on a mid phone: about 150–300 draw calls and about 300–500k triangles at 30 fps. The Quarter and the Mile are 2–4× over it.
- **Web build:** `index.wasm` is 35.4 MB (8.0 MB gzipped). `index.pck` is **38.2 MB** (37.1 MB gzipped, because textures don't compress). The page reached the menu in about 60 s at software speed.
- **The `.pck` carries dead weight:**
  - `sol.scn`, the unused old Sol, 1.46 MB;
  - the `*_rig.scn` copies of all three enemies, 4.6 MB. These are used only by the bosses, and duplicate the `*_anim.scn` files;
  - the `sol_unrigged` textures.
- **Sol's triangles:** body 37k, coat 29k, head 26k, hands 2×10k, sword 11k (a second 11k sword mesh is also present). That is about **135k triangles for the hero alone**.
- **Camp probe** (native): the camp at (150, −92) had 4 members idle with 0 moving from 22 m away. At 9 m it woke, with 2 attacking and 2 circling. **Idle and aggro work.**

---

## 1. Visuals — 5 / 10

**What's good**
- The night Old Quarter reads as the concept: wet asphalt, lantern-post lamps with halos, iron galleries, lit shopfronts, and the cathedral with an emissive rose window (`sol_full_back.png`, `sol_sprint_gameplaycam.png`).
- The Velvet Mile at night is the best shot in the game: magenta neon, streetcar rails, a long avenue (`dist_velvet_mile_night.png`).
- The menu lair hits the concept's layout and warmth: chandelier, red fridges, the string board, the brass lamp, Sol at the bench and Nia with her tablet (`menu_01.png`, `web_desktop_01_menu.png`).
- The red Curfew wall reads on the horizon from every district.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| V1 | High | `map/wilds.gd` (pines and bayou trees) | `dist_pines_night.png`, `dist_pines_day.png`, `sol_sprint_side_3.png`: trunks are untextured 1 m cylinders and canopies are stacked flat cones. Nothing like `06_hollow_pines.jpg`. | Give the trunks a bark texture with vertex-colour variation and taper. Swap the cones for 2–3 generated pine models in a MultiMesh, plus alpha-card branches. Add a fog layer under the canopy. | M | Yes: 2 pine models + 1 cypress with moss, ≈15 |
| V2 | High | `map/cemetery.gd` | `dist_cemetery_night.png`, `dist_cemetery_day.png`: the tombs are flat-shaded boxes with gabled lids. | Make 3 tomb variants: an above-ground vault with a cornice, iron railings and a cross. Use a stone texture with streak stains from `city.gd` `_stone_textures()`. Reuse the angel prop on some plots. | M | Optional: 1 tomb model, 5 |
| V3 | High | `hunt/poi_dressing.gd` (Hollow Camp) | `hunt_06_camp_fight.png`, `sheet_hunt1.png`: the trailer is a white box with two lit windows. | Build a trailer from parts (rounded ends, corrugated side, the `corrugated` material that already exists, a door step), plus a fire barrel with an OmniLight and smoke particles. | M | Optional: 1 trailer model, 5 |
| V4 | Med | `city.gd` (crosswalk or slab near the plaza, around (0, 0, 28)) | `dist_quarter_plaza_night.png` and `dist_quarter_plaza_day.png`: a bright white rectangle floats in the foreground at the bottom of the screen. | Find the quad (probably a crosswalk slab using an unshaded or white material, or an un-tinted vertex colour) and give it the crosswalk material. | S | No |
| V5 | Med | `atmosphere.gd` rim and fill lights (`SOL_LIGHT_LAYER`), plus the coat material | `sol_full_front.png`, `sol_neck_34.png`, `menu_06_sol_close.png`: the black leather coat renders silver-grey with a chrome-like specular. The concept calls for a black or dark-brown coat. | Lower the rim and fill energy by about 50%. Set the coat material to albedo ×0.35, roughness 0.55–0.7 and specular 0.3. Check it in the menu lamp light too. | S | No |
| V6 | Med | `city.gd` shopfront textures (`_shop_textures`) | `sheet_moves1.png`: the shop windows are flat orange cards with black silhouette cut-outs. They read as clip art at gameplay distance. | Add an interior-mapping shader (fake room depth), or at least a parallax offset layer and a dim glass reflection. Make the silhouettes rare (1 in 6 windows). | M | No |
| V7 | Med | `hunt/deploy.gd` (ladder / Pier Six) | `hunt_03b_deploy_d.png`: a huge white overexposed sun disk fills half the frame in the Descent. In `hunt_01_deploy_a.png` the camera starts in a dark corner under the pier. | Clamp the sky sun size and energy when the camera is low, keep the deploy camera framed on Sol, and check all 6 deploy types. | S | No |
| V8 | Low | `map/docks.gd` | `dist_docks_night.png`, `dist_docks_day.png`: the containers read well, but the quay is a flat grey floor and the shot is mostly a black fence. | Add puddles, bollards with rope, sodium pools, and spawn points outside the fence. | S | No |
| V9 | Low | Cathedral plaza trees | `sol_full_back.png`: the bare trees are flat black cut-out cards. | Use 3–4 crossed cards with a lit alpha texture, or the generated cypress. | S | Covered by V1 |

## 2. Characters and animation — 5 / 10

**What's good**
- Sol's head is a believable, AI-built face with a beard and tied-back locs (`sol_face_front.png`, `sol_head_side.png`). The neck seam is clean.
- Nia matches the concept (glasses, cardigan, tablet, watch) and is the best-looking character (`menu_07_nia_close.png`).
- The sword moves are real mocap from the library: the triple combo, charged slash, thrust, sprint slash, judgment, parry and stance (`sheet_moves1.png`, `sheet_moves2.png`). They read as real swordplay, which was an owner goal.
- The coat trails and folds when sprinting and settles when stopped (`sol_sprint_side_0..3.png`, `sol_stopped_side.png`). The spring-bone coat is a genuine win.
- The enemies are auto-rigged and clip-driven, with a transform tween.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| C1 | High | `hunt/bosses/boss_base.gd:1-12, 131-180`; `velvet_fang.gd`, `abomination.gd`, `hollow_alpha.gd` | The code says "No new art": the bosses are the old `*_rig.scn` enemies scaled up, tinted and posed procedurally (not the clip-driven `*_anim.scn`). Marcus Crane, the "speed vampire who is Sol's mirror", is a 1.x-scale street vampire. The Alpha is a 1.65× wolf. | **Marcus Crane:** a detailed model (suit, long coat) with a rig and a clip set (sprint, slash, dash), roughly 12.5 + 8 credits. **Alpha:** a unique grey matriarch wolf (a standard model and rig, 13). Move all bosses to `*_anim.scn`-style clip playback through `enemy.gd`'s `_play` path. | L | Yes, about 34 |
| C2 | High | `items/weapon_visual.gd`, `sword_wrist.gd`, `sol_modular_anim.gd` | `sol_full_front.png`, `sol_full_back.png`, `move_light3_b.png`: in idle and locomotion the blade is edge-on or hidden behind the body. What reads is a **white glowing disc** at the hand (the guard, or a bright emissive or unshaded part). The owner asked for a natural grip. | Make the guard's material match the blade (metal, not white or emissive). In locomotion, rotate the wrist so the blade sits at about 30° down and back and is visible from the follow camera. Add a thin rim highlight to the blade edge only. | S | No |
| C3 | High | `enemy.gd:_anim_hit` + `player.gd:_finisher` (607) | `move_finisher_a.png`, `move_finisher_b.png`: in the execution Sol crouches under a werewolf that stays standing and doesn't react. There is no paired victim animation. | During `finisher_t`, drive the victim: face Sol, play `hit` at speed 0.5, and on the strike frame play `death` with a knockback toward Sol's forward. Offset Sol to a fixed 1.2 m in front of the victim before the clip. Add a blood burst and a 0.12 s hit-stop. | M | No |
| C4 | Med | `hunt/deploy.gd` (ladder climb) | `hunt_03b_deploy_d.png`: Sol climbs out with his arms straight out in a near T-pose, because no climb clip exists. | Buy a climb or ledge-up clip, or blend `jump` with a crouch. For the ladder and manhole, do a short crouch-rise using the `idle` and `jump` clips. | S–M | Optional: rig plus clip, 8 |
| C5 | Med | `assets/characters/sol/*`, head | There is no facial animation or lip-sync. Sol's lines play over a frozen face in the menu. | Add a cheap jaw-bone or blendshape flap driven by voice amplitude (`AudioEffectSpectrumAnalyzer` on the Voice bus), plus eye blinks. It's 30–40 lines in `sol_bench_pose.gd` and the Nia equivalent. | M | No |
| C6 | Med | `sol_moves.gd` light3 / `sol_modular_anim.gd` | `sheet_moves1.png` row 3: the third combo hit leaves Sol facing about 90° off from his gameplay facing, and drifts him about 1 m sideways. The clip's root rotation stays in. | Strip root rotation from the combo3 cut in `tools/build_sol_modular.gd` (as was done for root translation), or counter-rotate `visual` over the clip. | S | No |
| C7 | Low | `enemy.gd` model set | Only 3 enemy bodies (vampire, wolf, civilian). The elites are the same body with a fresnel bubble (`hunt_06_camp_fight.png`). | Add one Courtier model (an elegant duelist) and one Thrall (feral). | M | Yes: 2 × (5 + 8) = 26, or a lower-cost single 13 |
| C8 | Low | Sol, triangle count | About 135k triangles for the hero, plus a duplicate 11k sword mesh. | Decimate the body and coat to about 15k each for the web, and drop the hidden sword. | S | No |

## 3. Combat and game feel — 5 / 10

**What's good**
- The moves are data (`sol_moves.gd`), with strike frames, lunge, hit-stop, shake and rumble per move.
- The attack set: a 3-hit combo, a held charged slash that staggers, a dash thrust, a sprint slash, an execution, and a parry that staggers.
- Attack tokens (at most 2 attackers while the rest circle), locked strike directions, perfect dodge with slow-mo, and the bite that heals by blood type.
- In the native probe, enemies at camps idle until close, then engage in pairs.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| G1 | High | `player.gd:_attack()` (472–518), `sol_moves.gd` `delay:false` | Light and heavy combo damage lands **on the button press**, before the blade moves (`delay: false`). Hits register before the swing reads on screen. | Use the `pending` strike path that the specials already use, for the combo too. Start the clip just before the strike so the delay is about 80–120 ms, and add input buffering of about 0.25 s so chaining still feels instant. | S | No |
| G2 | High | `enemy.gd:466-475` | Every enemy has exactly **one** attack (a 0.38 / 0.45 s wind-up, then a swipe). There is no lunge, grab, leap or ranged attack. | Add a second attack per type as data: vampire lunge (6 m dash, dodgeable) and wolf leap (2 m radius slam), each with a ground decal telegraph like the bosses'. Reuse `boss_base`'s attack dictionary format. | M | No |
| G3 | Med | `player.gd:_physics_process` (velocity set directly) | Movement still starts and stops instantly (the same note as round 0). It feels weightless. | Add an 0.08 s acceleration ramp and an 0.12 s stop, plus a sprint-turn skid. | S | No |
| G4 | Med | `player.gd` camera spring (`spring.collision_mask = 1`) | `hunt_06_camp_fight.png`: in a fight under the pines the camera clips into tree planes, and half the frame is bark. | Put the trees and foliage on a collision layer the SpringArm tests, and add a camera-occluder fade (dither) for trunks within 1.5 m. | S | No |
| G5 | Med | Hit feedback | There are no blood decals, no hit-direction flash on Sol, and no enemy health bars. An enemy's progress toward stagger is invisible (also noted in round 0). | Add a thin health bar over an engaged enemy that turns red at the stagger threshold, a screen-edge damage arrow, and a blood decal pool on kills (a MultiMesh of quads). | M | No |
| G6 | Med | `player.gd` Frenzy | Frenzy is still a pure buff (round-0 bug 9). | Lock out the parry and auto-target the nearest living thing while it lasts. | S | No |
| G7 | Low | Parry | The parry window is 0.3 s on its own C or L3 button. That's fine, but L3 is an awkward parry on a pad. | Offer LB as the parry and move quick-use to the D-pad, or make it a rebind option. | S | No |

## 4. Nightreign loop and level design — 6 / 10

**What's good**
- **The structure matches the brief.** The hub (charms, Sunmarks, record) leads to an edge deploy (8 points, 6 types). Then come 21 seeded sites (4 nests, 4 camps, 3 markets, 3 landmarks with field bosses, 4 chapels, 3 merchants) across 6 districts. The 2-stage Curfew follows, then 3 night bosses over 2 days and a Final Night, then results and the return to the hub. Rank-ups bring Vow choices, and loot comes in 4 rarities.
- **The smoke test proves the plumbing:** deploy away from the plaza; nothing chases at the start; stragglers idle; the camp idles and then aggros; clearing pays out; the Curfew shrinks and hurts outside; the boss spawns at closure; a boss kill advances the day; a revive, then death leads to results; charms persist.
- **The map screen is clear:** districts, icons, the Curfew now and where it closes next (`web_mobile_08_map.png`).

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| L1 | High | Replayability (`hunt_config.gd` BOSSES) | The night bosses come in a fixed order (Alpha, then Marcus, then the Abomination). Only the arenas shuffle. Site types never change by day. | Draw Night 1 and Night 2 from a pool of 3–4 (add a field boss promoted to night boss, e.g. the Blood Knight). Add a seeded "Hunt modifier" per run (Blood Moon, Fog, Sun-starved). | M | No |
| L2 | High | Districts outside the Quarter and the Mile | `sheet_day.png`, `sheet_night2.png`: the pines, cemetery and bayou are open floors with few landmarks. The Docks are a fenced yard. There is little reason to cross them except for sites. | Per district, add 2–3 "micro-POIs" with loot and verticality (a container top, a crypt interior, a sunken porch) and visible landmark lights. See V1–V3 for the art. | M | Covered by V1–V3 |
| L3 | Med | Leveling depth | Only ranks bought at a chapel give power. There is no in-run choice from kills, and the 17 Vows are mostly small stat bumps. | Add an in-run "blood rite" pick on every boss kill (choose 1 of 3 strong perks), plus 4–6 build-defining Vows (for example, the dash leaves 3 clones). | M | No |
| L4 | Med | Pacing (`hunt_config.gd` TIMINGS normal) | Explore takes 215 s on a 430 m map at 13 m/s sprint. That covers 2–4 sites per day, with no traversal tools (the bible's wall-run and grapple). | Add a sprint-vault onto 1 m ledges and rooftops in the Quarter, or a single "blood leap" (a long jump on dash+jump). Show the Curfew's next centre at the start of the day so routes can be planned. | M–L | No |
| L5 | Low | Results / extraction | There is no extraction moment after the final boss; the run just ends. The `hunt_extract` line says "Get to extraction". | Either make dawn after the Final Night an extraction walk to the Undercroft arch (30 s) or change the line. | S | 1 voice line, 0.25 |
| L6 | Verify | `hunt_director.gd` 3-boss win | It wasn't verified end to end this round. The smoke test stops after boss 1. | Add a smoke check: kill all three bosses via `debug_skip_to`, then assert `won == true` and that results are visible. | S | No |

## 5. Audio and dialogue — 6 / 10

**What's good**
- 57 voiced lines with coloured speaker subtitles, priorities and cooldowns.
- The menu banter between Sol and Nia has character ("If you die out there, I'm keeping the coat.").
- Music crossfades between lair, exploration and combat.
- 3D sword hits, wet footsteps, rain and thunder.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| A1 | High | `hunt/bosses/*.gd`, `curfew_ring.gd`, `deploy.gd` | `grep Audio.` finds **zero** calls in the bosses, the Curfew ring and the Descent. The boss slams, swipes, blood bolts and blinks, the Curfew wall and the manhole or ladder are silent. Only an intro howl plays. | Add these SFX: boss slam impact, a heavy swipe whoosh, a blood-bolt cast, a blink pop, a Curfew drone loop (3D, at the wall) with crackling lightning, a manhole clank, a landing thud and a ladder creak. Hook them in `boss_base._resolve` and the ring's `_process`. | S | Yes: 8 SFX × 0.5 = 4 |
| A2 | Med | `player.gd:_parry_success` | The parry reuses `sword_hit`. A parry needs a bright steel clang to teach the window. | Add `parry_clang` and Sol hurt grunts (3 variants). | S | Yes: 4 SFX, 2 |
| A3 | Med | `audio.gd` music | One combat track covers every fight and all three bosses. | Write a boss theme per night, or at least one boss-only track plus a final-night layer. | S | Music generation, about 1–2 (if priced like SFX) |
| A4 | Med | `data/dialogue.json` | These lines contradict the game:<br>• `hunt_deploy_1` says "Three marks on the map", but there are 21 sites;<br>• `poi_cleared_1` says "Nest's clear" for camps and markets too;<br>• `boss_alpha_intro` says "She's big", but the Alpha model is male and its title is "Mother Wren's Firstborn";<br>• `hunt_extract` mentions an extraction that doesn't exist. | Re-record 4 lines, or re-key them: add `poi_cleared_camp`, `_market`, `_landmark` variants. | S | Yes: about 6 lines, 1.5 |
| A5 | Low | Voice coverage | The night bosses' mid-fight lines (phase 2) and the field bosses have no voice. Elites have no barks. | Add 6–8 lines: phase-change taunts for each boss and one bark each for the Courtier and the Pack Leader. | S | Yes: 2 |

## 6. UI/UX — 4 / 10

**What's good**
- KB/M and controller are complete and documented. The menu, hub, options, pause and the Coat all work with a pad.
- The compass strip with site icons and the phase countdown are readable.
- The map screen is clean.
- The options are thorough (quality, render scale, volumes, subtitles, invert Y).

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| U1 | **Critical** (owner goal) | No touch layer; `hud.gd:118` says "Touch controls are not supported yet." | The owner wants phones. On Pixel 7 the game can't be played at all. | Add `ui/touch_controls.gd`: a left virtual stick, right-side look drag, and buttons for attack (hold for charged), dash, jump, bite/interact, parry, map and the Coat. Show it only when `DisplayServer.is_touchscreen_available()`. Map the controls to the existing InputMap actions with `Input.action_press`. | M | No |
| U2 | High | `project.godot` stretch (`canvas_items` + `expand`) and menu layout | `web_mobile_01_menu.png`: in portrait, Sol and Nia are cropped off the right edge, the title sits over the string board, and the footer text is about 6 px. `sheet_mobile.png`: the hub panel is tiny, and the HUD text is unreadable. | Lock landscape where possible and show a "rotate your phone" overlay in portrait. In landscape, scale the UI by `min(w/1280, h/720)` with a minimum of 1.0 in logical pixels, and frame the lair camera so Sol and Nia stay in view at narrow aspects. | M | No |
| U3 | High | `ui/ui_style.gd:19-20` (`SystemFont` "Cormorant Garamond"…) | Native: serif title (`menu_01.png`). Web: falls back to sans (`web_desktop_01_menu.png`, `web_desktop_04_hub.png`). Browsers have no system fonts for Godot. | Bundle an OFL font, for example Cormorant Garamond as a `.ttf` (about 300 KB), as a `FontFile` in `assets/ui/fonts/`. | S | No |
| U4 | Med | `hud.gd` bottom-left hints | Every gameplay shot shows four lines of KB hints that never go away, and they list free-roam actions: "F drink at the Undercroft" and "T rain". | Show context hints only for the first 60 s or when an action first becomes possible. Drop the free-roam lines in a Hunt. Swap the glyphs for a pad when one is in use. | S | No |
| U5 | Med | `hunt/hub_panel.gd` | `menu_03_hub.png`: the hub is a text form over a blurred lair. Nia is "in the room" but not part of the UI. | Frame the hub camera on Nia at the fridges or map table, with the armoury as cards over the weapon rack. Play `hunt_hub` when the hub opens. Show charm icons from `assets/ui/icons`. | M | No |
| U6 | Low | `main.gd:start_game` (`Input.mouse_mode = CAPTURED`) | Web console: `PAGEERROR: A user gesture is required to request Pointer Lock.` The capture after the scene change has no user gesture behind it. | On the web, show "Click to take the hunt" over the Descent and capture inside the click handler. | S | No |
| U7 | Verify | The Coat, level-up and results screens | The inventory and level-up captures were cut short this round. Results were seen on the web (`web_desktop_06_hunt.png`) and read well. | Recapture them next round. | — | — |

## 7. Story and presentation — 5 / 10

**What's good**
- The bible remains a strong pitch: the bite as morality, Lucien and Seraphine, the Pack as working families.
- The Hunt uses the cast well in comms: Nia's briefings, Lucien's Curfew broadcast, Reyes on the scanner, Marcus's intro.
- The menu banter sets the tone in five seconds.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| S1 | High | Hub → Hunt | There is no framing: why is Sol hunting, and what is the Curfew? The first Hunt starts cold. | Add a 30–45 s still-and-voice intro the first time: 4–5 painted stills (the concept art is already there as reference) with Nia and Lucien VO, explaining the Accord breaking, the Curfew and "three nights to find who's framing you". Skippable. | M | Yes: 5 stills 1.25 plus 6 lines 1.5 |
| S2 | Med | Bosses | The bosses have names, but a death line is their whole story. Seraphine is never seen; her Abomination stands in. | Give each boss a 2-line pre-fight exchange with Sol, and show Seraphine on a rooftop (a Nia-style model) on the Final Night. | M | Yes: 1 detailed model, 12.5, plus lines, 1 |
| S3 | Med | Meta progression | Wins add nothing to the story. | Unlock one "case file" text and voice log per boss kill in the hub (the Bloodline journal from the bible, in its smallest form). | S | Yes: about 6 lines, 1.5 |
| S4 | Low | `STORY_BIBLE.md` §12 | It still says UE5 and MetaHuman are the way to build it, which contradicts the actual Godot and browser direction. | Add a short §12b "Browser build" with the real toolchain and its limits. | S | No |

## 8. Code quality and architecture — 6 / 10

**What's good**
- **Data-first design:** `hunt_config.gd`, `map_layout.gd`, `sol_moves.gd` and `item_db.gd`.
- **Small integration points:** HUNT, AUDIO, MAP and PROGRESSION hooks, 84 marked.
- **Readable docs at the top of every file.**
- **Tests:** a 138-check smoke test in CI before every deploy. The CI also does a fresh import and fails on VRAM-compressed character textures, and cache-busts the `.pck`.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| K1 | Med | `city.gd` (3,918 lines), `menu/lair_set.gd` (1,352), `tools/build_sol_modular.gd` (1,575) | God files: city.gd does textures, materials, batching, Old Quarter buildings, the plaza, the lair entrance, props and HLOD. | Split city.gd into `city/textures.gd`, `city/materials.gd`, `city/batcher.gd`, `map/quarter.gd` (as already done for docks, velvet, wilds and cemetery) and `city/props_place.gd`. No behaviour change; the smoke test guards it. | M | No |
| K2 | Med | Whole codebase | 0 `class_name`, 27 untyped `var main`/`var director`, 131 `.get("…")`/`has_method` duck-typing calls. Errors surface at runtime only. | Add `class_name` to `Main`, `Player`, `Enemy`, `HuntDirector`, `BossBase` and `Poi`, and type the `main` and `director` fields. Start with player.gd, enemy.gd and hunt_director.gd. | M | No |
| K3 | Low | Dead paths | `player.gd:_build_model`/`_build_primitive_body`, `sol_anim.gd`, `assets/characters/sol/sol.scn` (1.46 MB in the pck), the free-roam spawner and lair drink in `main.gd`, and `sol_unrigged*`. | Delete the old Sol path and assets, and keep free roam only as a test fixture. | S | No |
| K4 | Low | `boss_base.gd:15` and `enemy.gd:49` | `MODEL_PATHS` is duplicated, and the bosses use a different animation system (procedural on `*_rig`) from the enemies (clips on `*_anim`). | Share one model registry. Move the bosses to clips (see C1), then drop the `*_rig.scn` files (4.6 MB). | M | Covered by C1 |
| K5 | Low | Headless log noise | `smoke.log` has 3,846 × `ERROR: Parameter "m" is null` (`mesh_get_surface_count`, dummy renderer). Real errors can hide in CI logs. | Guard the mesh queries with `if RenderingServer.get_rendering_device() or not DisplayServer.get_name() == "headless"`, or skip the surface reads when headless. Add a CI step that fails on new `SCRIPT ERROR` lines. | S | No |
| K6 | Low | `settings.gd:187` | `window_set_vsync_mode` is called on the web, which logs a console error on every load. | Skip the call when `OS.has_feature("web")`, and hide the V-Sync option there. | S | No |

## 9. Web and performance — 3 / 10

**What's good**
- Single-threaded export (any host works); CI builds and deploys every push.
- Web-safe texture imports are enforced.
- The menu runs and looks almost identical to the native build in Chromium (`web_desktop_01_menu.png`).
- No script errors in the console.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| W1 | **Critical (verify first)** | Hunt scene in the browser | `web_desktop_05_loading_or_deploy.png`, `web_mobile_05/06/07`: after Begin the Hunt, the browser shows only a sky and fog gradient. There is no city and no Sol, on desktop 1280×720 and on Pixel 7, while the HUD, compass, map and subtitles all work. The native Compatibility renderer shows the city fine from the same menu path (Sol on the floor at the deploy point, camera behind him). The Hunt then ends with Sol dying to the Curfew unseen (`web_desktop_06_hunt.png`). This was **SwiftShader, not a real GPU**, so it may be a software-GL limit. | 1) Open the Pages build on a real desktop GPU and a real phone. 2) If it reproduces, add a `?debug` overlay printing the camera position, the current camera's path, and the draw-call count. 3) Prime suspects: the deploy camera staying current after a sync load with a huge first-frame delta; a shader in `wet_materials.gd` failing to link in WebGL2 (a failure makes every object using it invisible; Sol's materials are separate, so also check the camera); `fog_scale`/far plane on the web tier. 4) Add a Playwright CI smoke test that compares a gameplay screenshot to a "not mostly sky" heuristic. | M | No |
| W2 | High | Draw calls and triangles (`city.gd` batching, `CHUNK`/`MAIN_RANGE`, props) | Velvet Mile: 1,047 draw calls and 1.14M primitives. Old Quarter: about 710–765 and 830–900k. The menu: 716 and 513k. That is 2–4× a phone budget. | Merge props into MultiMeshes per type per chunk, drop `MAIN_RANGE` from 115 to about 70 on the web tier with HLOD beyond, give the generated props LODs (the importer warning shows LOD gen already runs), and shrink the shadow-casting set. Target ≤300 draws and ≤400k triangles on the web tier. | M | No |
| W3 | High | Touch / phone | See U1 and U2. The phone experience is "watch the menu". | Same as U1 and U2. | M | No |
| W4 | Med | Download size | The `.pck` is 38.2 MB, barely compressible, plus 8 MB of gzipped wasm. On a phone on 4G that's 30–60 s before the menu. The pck includes about 6 MB of dead or duplicate assets (`sol.scn`, `*_rig.scn`, `sol_unrigged`). | Delete the dead assets (K3, K4). Halve the 2K PBR textures of small props (hydrant, news box, trash) to 512–1K. Use mono 96 kbps for music. Show a real progress bar in a custom HTML shell. | S–M | No |
| W5 | Med | `post_fx.gd:8` (`hint_screen_texture`) | Chromium warns "GPU stall due to ReadPixels". There is a full-screen copy every frame on the web tier. | On the web tier, fold grain and vignette into the Environment adjustments, or use a cheaper overlay `ColorRect` without screen-texture sampling. | S | No |
| W6 | Low | Load path | Sync load on the web: the navmesh bake (0.9–1.5 s native) and the city build happen in one frozen frame behind "Loading…". | Bake the navmesh at import (save a `.res`), or bake per district over several frames. | M | No |

---

## Top 15 fixes for round 2

Ordered by score gain per effort. They are grouped so that 4 agents can work in parallel without touching the same files.

### Group A — Web shell, phone and UI (agent 1)
Files: `scripts/hud.gd`, `scripts/ui/hunt_hud.gd`, `scripts/ui/ui_style.gd`, `scripts/menu/menu_style.gd`, `scripts/menu/main_menu.gd`, `scripts/menu/lair_set.gd` (camera framing only), `scripts/settings.gd`, `scripts/post_fx.gd`, `scripts/hunt/deploy.gd`, `scripts/hunt/hub_panel.gd`, a new `scripts/ui/touch_controls.gd`, `project.godot`, `export_presets.cfg`, `assets/ui/fonts/*`, `.github/workflows/web.yml`.

1. **W1: the empty-sky Hunt in the browser.** Confirm it on a real GPU. Then fix the deploy camera handoff and shader link on the web tier, and add a Playwright "not mostly sky" check to CI. *(S–M; Web +2, Overall +1.)*
2. **U1 + W3: touch controls.** *(M; UI +2, Web +1.)*
3. **U2: phone layout.** Landscape lock or a rotate prompt, a UI scale floor, and a lair camera that keeps Sol and Nia framed. *(M; UI +1.)*
4. **U3 + K6 + U6 + U4: web polish.** Bundled serif font, no V-Sync call on the web, pointer lock taken on a click, context-only HUD hints. *(S; UI +1.)*
5. **W5 + W4 (shell part): cheaper post FX and a progress bar.** Drop the full-screen screen-texture pass on the web tier. Add an HTML-shell progress bar. *(S; Web +0.5.)*

### Group B — Sol and combat feel (agent 2)
Files: `scripts/player.gd`, `scripts/sol_moves.gd`, `scripts/sol_modular_anim.gd`, `scripts/sword_wrist.gd`, `scripts/items/weapon_visual.gd`, `scripts/enemy.gd`, `tools/build_sol_modular.gd`, `scripts/atmosphere.gd` (only the Sol rim and fill section).

6. **G1: combo damage on the strike frame,** with an input buffer. *(S; Combat +1.)*
7. **C2 + V5: blade and coat read.** Non-white guard, wrist angle that shows the blade, darker matte leather coat, rim and fill halved. *(S; Characters +1, Visuals +0.5.)*
8. **C3 + C6: execution with a victim reaction.** Also strip the combo3 root rotation. *(M; Characters +0.5, Combat +0.5.)*
9. **G2 + G5: one more attack per enemy type** (vampire lunge, wolf leap) with ground telegraphs, plus engaged-enemy health bars and a stagger threshold. *(M; Combat +1.)*
10. **G3 + G4: movement and camera.** Acceleration and stop ramps, and the camera avoids trees and dithers occluders. *(S; Combat +0.5.)*

### Group C — World art and frame cost (agent 3)
Files: `scripts/city.gd`, `scripts/map/wilds.gd`, `scripts/map/cemetery.gd`, `scripts/map/docks.gd`, `scripts/props.gd`, `scripts/hunt/poi_dressing.gd`, `assets/props/map/*`.

11. **W2: draw-call and triangle budget on the web tier.** Prop MultiMeshes per chunk, a shorter `MAIN_RANGE` with HLOD, fewer shadow casters. Target ≤300 draws and ≤400k triangles. *(M; Web +1.)*
12. **V1 + V9: Hollow Pines and the bayou trees.** Generated pines and cypress as MultiMeshes, bark texture, ground fog. *(M; Visuals +1. ≈15 credits.)*
13. **V2 + V3 + V4: cemetery tombs, the camp trailer and fire barrel, and the white floating quad.** *(M; Visuals +0.5, Loop +0.5. 0–10 credits.)*

### Group D — Bosses, audio and story (agent 4)
Files: `scripts/hunt/bosses/*.gd`, `scripts/hunt/curfew_ring.gd`, `scripts/hunt/hunt_config.gd` (the BOSSES pool), `scripts/hunt/hunt_director.gd` (boss pick and the intro trigger only), `scripts/audio/audio.gd`, `scripts/audio/dialogue.gd`, `data/dialogue.json`, `docs/DIALOGUE.md`, `assets/audio/*`, `assets/characters/<new boss>/*`, `tools/build_enemy_anims.gd`, `tests/smoke_test.gd` (the 3-boss win check).

14. **A1 + A2 + A4: the missing sounds and wrong lines.**
    - Add these SFX: boss slam, swipe, bolt, blink, Curfew drone, manhole, landing, parry clang, hurt grunts.
    - Fix the 4 contradicting lines.
    - Add the L6 smoke check for a full 3-boss win.

    *(S; Audio +1.5. About 8 credits.)*
15. **C1 + L1: a real Marcus Crane** (a detailed model, rig and clips) and clip-driven bosses, plus a shuffled night-boss pool. *(L; Characters +1, Loop +0.5. About 21–34 credits.)*

**Credit budget for this list:** about 45–60 of the 80 available. That is 8 for audio, 21–34 for boss models, 15 for trees, 0–10 for props. Keep about 20 in reserve for the S1 intro stills and voice (about 3) and fixes.

**Expected scores after round 2, if all 15 land:** Visuals 6.5, Characters 6.5, Combat 7, Loop 7, Audio 7.5, UI 7, Story 5.5 (6.5 with S1), Code 6.5 (7 with K1/K2), Web 6.5, Overall 6.5–7.

---

## Ceiling

Be honest with the owner about what this toolchain can reach. The toolchain: Godot 4.3 in a browser on the Compatibility renderer (WebGL2), AI-generated meshes and textures, library mocap clips, AI voices, and no actors or performance capture.

| Category | Realistic ceiling | Why it stops there |
|---|---|---|
| Visuals | **7–7.5** (8 on native Forward+) | WebGL2 Compatibility has no volumetric fog, no SSR, no real GI and a weak shadow budget. "Until Dawn" realism needs path-traced or baked GI, film-grade materials and dense hand-made sets. Strong mood (wet streets, practical lights, fog cards) is reachable; photorealism is not. |
| Characters and animation | **6.5–7** | AI meshes have messy topology and baked lighting in the albedo; there is no facial rig, so no performance. Library mocap reads well for the body, but there are no bespoke animations, no paired takedowns from capture, and no cloth beyond spring bones. A jaw flap and blinks are the facial ceiling. |
| Combat and game feel | **8–8.5** | Nothing in the toolchain blocks great feel. It's tuning, VFX, sound and camera. The only limit is mocap coverage for bespoke moves. |
| Nightreign loop and level design | **8** | The systems scale. The limit is hand-made content per district and team time, not tech. |
| Audio and dialogue | **8** | AI voices are good for barks and comms, but they lack an actor's range in big emotional scenes. Music and SFX can reach 8+. |
| UI/UX | **8.5–9** | Fully achievable, including touch. |
| Story and presentation | **6.5–7** | Without facial performance there can be no Until-Dawn-style cutscenes. Stills plus voice, in-engine framing and text logs can tell the story well, but not cinematically. |
| Code quality | **9** | Achievable with refactors and typing. |
| Web and performance | **7.5–8** | A 40–70 MB download and single-threaded WebGL2 cap phone performance. Low-end phones will need a "lite" tier (no rain, a short draw distance, no post FX). Mid and high phones can hold 30 fps after W2. |
| **Overall** | **about 7.5** | A polished, moody, fast browser action-roguelite is realistic. "Ultra-realistic prestige horror" in a browser with AI assets is not. A native desktop Forward+ build from the same project could add about +0.5 to Visuals and Overall. |

**The only routes to 9–10 on visuals, characters and story** are a native or console engine (Forward+ in Godot, or UE5 as the bible's §12 says), real performance capture (even an iPhone ARKit face capture of an actor), and an artist pass on the hero characters. The owner should set the target as "Until Dawn mood and structure, not Until Dawn fidelity".
