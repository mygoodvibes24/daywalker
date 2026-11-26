# DAYWALKER: Blood and Moon — Critic Report, Round 3

Reviewed: commit `143d4d6` (branch `claude/day-walker-game-concept-mz8vvv`, deployed as `index-143d4d6da0.pck`), 2026-11-26.
Bar: **Elden Ring and Nightreign** for look, animation, action and gameplay. A 10 means "stands next to Elden Ring". A 5 means "a competent prototype with real assets".
No game code was changed. Evidence is under `/tmp/claude-0/-home-user-daywalker/dd1b8b5c-f35a-5096-ac5f-5ff9b687f52e/scratchpad/critic_r3/`:
- `nat/`: native Compatibility captures.
- `fwd/`: one Forward+ view through lavapipe.
- `web/`: the deployed build in Playwright.
- Contact sheets: `sheet_bosses.jpg`, `sheet_sol_a.jpg`, `sheet_sol_b.jpg`, `sheet_arts.jpg`, `sheet_web.jpg`.

I also used the QA round 3 evidence (`scratchpad/qa_r3/`) for the tier views, the Undercroft, the phone and the settings.

**The lair hub and wardrobe are in progress** (another agent is building them). They are noted, not scored.

## Score table

| # | Category | R2 | R3 | Δ | One-line reason |
|---|---|---|---|---|---|
| 1 | Visuals | 5.5 | **6** | +0.5 | **Up:** the plaza on High now reads as the concept: cathedral, rose window, galleries, sedans. The graveyard, crows, Undercroft crypt and plaza oaks are real places. **Still down:** the asphalt still glitters on Medium and High, the Velvet Mile is grey towers by day, every boss arena is drowned in Curfew red, and Sol is a black shape at night. |
| 2 | Characters and animation | 5.5 | **6.5** | +1 | **Up:** Marcus and the Abomination have their own bodies and clips. Sol walks, crouches, carries the sword on his back, and draws and re-sheathes it with IK. **Still down:** he T-poses through every Descent, the Alpha, Knight and Abomination keep the lava veins and shield bubble, there is no face animation, and the 9 weapon types are mostly re-timed sword clips. |
| 3 | Combat and feel | 6 | **7** | +1 | **Up:** lock-on, stamina, a Frenzy that costs, body-language telegraphs, the parry working in boss fights, bleed and poise, and 9 weapon types with Arts and combo routes. **Still down:** a halberd, scythe or whip moves like a sword, the Arts read as a label plus a white bloom disc, and the hit read is a flat orange silhouette. Feel at real frame rate is still unjudged. |
| 4 | Loop and level design | 6.5 | **7** | +0.5 | **Up:** the Blood Rite (pick 1 of 3), night modifiers, micro-POIs, the Undercroft duel with a named rival, the graveyard, longer streets. **Still down:** no traversal or rooftops, and the Docks and Velvet Mile are still flat corridors. The lair hub isn't scored yet. |
| 5 | Audio | 6.5 | **7.5** | +1 | **Up:** web audio is fixed. Every boss and the rival have their own hip-hop and industrial theme, and the creature SFX are wired. **Still down:** each theme is a 29–33 s loop (6+ repeats per fight) and nobody has listened to them yet. The crypt is silent, and there are no boss phase lines. |
| 6 | UI/UX | 6 | **6.5** | +0.5 | **Up:** the 5-tab settings panel is the best UI in the game, and the Rite card, ART button and crouch prompt are clean. **Still down:** the Coat soft-locks on a phone. There's no message queue: DAY 1, the night card, "SITE CLEARED", Art names and the boss intro all stack in the centre. The HUD is still text-heavy, the map is still a schematic, and the boss bar sits on the key strip. |
| 7 | Story and presentation | 6 | **6** | 0 | **Up:** Silas Crowe gets a name plate, Old Amos has a line, the bosses have names. **Still down:** none of R2's story items landed: no pre-fight beat, no Seraphine, no case files. The first shot of every Hunt is a T-posed hero behind a mirrored sign. |
| 8 | Code | 6 | **6.5** | +0.5 | **Up:** 355 smoke checks, a CI audio guard, a clean settings API, 12 `class_name`s, typed hunt and UI fields. **Still down:** `city.gd` grew to 4,148 lines, there are 404 `.get()` / `has_method` calls, and lambda-capture and `"m" is null` engine errors remain. |
| 9 | Web and performance | 5 | **6** | +1 | **Up:** gameplay views went from 500–1,000 draws to 107–295, with tiers, dynamic resolution and pre-warm. **Still down:** the `.pck` grew to 50.9 MB plus 8 MB of gzipped wasm, the map view is the most expensive frame (341–542 draws), there's no cache, and it has never been run on a real phone GPU. |
| 10 | **Overall** | 6 | **6.5** | +0.5 | A real action-roguelite now: build choices, a weapon arsenal, lock-on and stamina, bespoke bosses with their own music, and a frame budget that fits a phone. The polish layer between systems (the first shot, overlapping text, weapon identity, the red wash) keeps it out of the 7s. |

### Owner's playtest complaints: status

| Complaint | Status at `143d4d6` | Evidence |
|---|---|---|
| Frame rate | **Much better.** Draws are down 2–4×, with tiers from Very Low to High, dynamic resolution and pre-warm. The **map** (341–542 draws) and Forward+ (1,034 draws, 1.05M primitives on the plaza) are still heavy. Not measured on real hardware. | QA3 #8, `fwd/plaza_night.png` |
| No sound | **Fixed** on desktop and phone after the first gesture. | QA3 summary |
| Undercroft stairs and a rival | **Done.** A walkable spiral stair, a candle-lit crypt and Silas Crowe. The crypt itself is silent and dark (QA3 #9, #10). | `qa_r3/sheet_undercroft.jpg` |
| Sword on his back | **Done.** The scabbard on the back, draw and sheathe IK, and per-weapon mounts. | `nat/sol_day_idle_back.png`, `sol_day_resheathed_back.png` |
| Short streets | **Lengthened.** | Map |
| Graveyard look and crows | **Done.** Shed, open grave, mausoleum mix and crows. | `qa_r3/nat_views/medium_cemetery.png` |
| More weapons, moves, combos | **9 types, Arts and combo routes are in.** But most types re-cut the same ~12 sword clips, and the meshes are procedural (see C3). | `sheet_arts.jpg`, `arsenal_moves.gd` |
| Settings for weak devices | **Done and good.** | `qa_r3/web_a/a02–a06` |
| Real walk, crouch, arm at idle | **Done.** Bought walk and crouch clips, relaxed arm. The walk reads as a calm stroll (`sheet_sol_a.jpg`). | `nat/sol_day_walk_*.png`, `sol_day_crouch_*` |
| Blade-style hip-hop boss music | **In and wired**, six themes. **Not listened to by anyone yet**, and the loops are only 29–33 s (A1). | `assets/audio/music/` |
| Lair hub with a wardrobe | **In progress** (another agent). Not scored. | — |

### R2 fix groups: what landed

| R2 group | Landed | Still open |
|---|---|---|
| **A, asset integration** | Creature clips, Marcus and Abomination bodies (decimated to about 17k), Marcus without veins or bubble, the Alpha at 1.35×, boss themes, creature SFX, props and texture library. | The boss **pre-fight beat** (S1). The **Alpha, Knight and Abomination still wear the vein overlay and the shield bubble** (`sheet_bosses.jpg`). |
| **B, combat and Sol** | Body telegraphs (G1), lock-on (G2), Frenzy cost and stamina (G3, G4), neck, boots and hem texture fixes (C2, C3), blood spray and hit-stop (G7), sheath mounts. | The **hit rim saturates into a flat orange body** (C7 half done). The **scanned head** is still off (`USE_SCANNED_HEAD := false`). G5's dither-fade was replaced by hiding camera blockers. |
| **C, world and budget** | Frame budget (W1), HLOD, plaza oaks (V6), Velvet neon strips, graveyard and mausoleum (V7), the lake (V4, wadeable, boats). | **V1 glitter asphalt** (still on Medium and High, `qa_r3/nat_views/medium_quarter_st.png`). **V2** Velvet facades (still grey towers). **V3** Docks. **V5** red arena wash. **K1** split `city.gd` (it grew). |
| **D, UI, story, audio, shell** | `set_boss` music switching (A1). | **Nearly none of it.** No message queue (U1), no HUD diet (U2), no parchment map (U3), no case files (S3), no Seraphine (S2), no service worker (W2). |
| **E, loop and code** | Blood Rite (L1), modifiers (L4), micro-POIs (L2), dead assets removed (K4), `class_name`s and typing started (K2), `skip_to` boss in the arena (L5), navmesh errors gone on the web (K3). | Navmesh bake at import (W4). |

## How this was reviewed

**Native captures:**
- Compatibility under xvfb, 1280×720, Medium and High tiers, seed 4242, with a temporary capture script (deleted).
- What was captured:
  - Sol close up in daylight: 4 angles, face, walk ×6, run ×4, crouch idle and walk, draw ×6, drawn and re-sheathed.
  - 7 weapon Arts × 5 frames (katana, greatsword, hammer, scythe, whip, halberd, daggers).
  - All 4 night bosses in the arena: gameplay camera and portrait.
  - The plaza on High.
- **Forward+:** one plaza view on High through the lavapipe Vulkan driver.

**Web:**
- The deployed `143d4d6` build in Playwright Chromium (SwiftShader), desktop 1280×720 and Pixel 7 landscape, with `?autohunt&nointro&debug`.
- Both reached HUNT_READY (94 s desktop, 112 s phone). The console was clean.
- **Download:** `.pck` 50,877,690 bytes, wasm 8.1 MB gzipped.

**Also:**
- QA round 3's tier views, the Undercroft and phone sheets, and its draw tables.
- The code paths named below.
- Boss-music length and loudness with ffprobe and ebur128 (-11.9 to -13.7 LUFS, consistent).

**Limits:**
- Software rendering runs at about 1 fps, so **feel and timing are judged from code and frame sequences, not from play at speed.** A real-GPU pass is still missing from every round.
- My boss captures swap tonight's boss in by script, so the night card in those frames names Marcus over other bosses. That part is an artefact. The *stacking* of the night card with the boss intro is real.

---

## 1. Visuals — 6 / 10 (R2: 5.5)

**What's good**
- **The plaza on High** (`nat/plaza_night.png`): the cathedral with its rose window framed down a street of iron galleries, hanging moss, cobbles and 70s sedans. It's the closest frame yet to `01_plaza_night.jpg` and `12_old_quarter_avenue.jpg`.
- **The graveyard** (`qa_r3/nat_views/medium_cemetery.png`, `medium_shed.png`): varied headstones, crosses, obelisks, iron fencing, the shed with a lit window, and crows. R2's grid of identical boxes is gone.
- **The Undercroft crypt** (`qa_r3/sheet_undercroft.jpg`): candle clusters, warm stone and a gothic window. It reads as `08_undercroft.jpg` in mood.
- **The bayou on the phone** (`web/phone_01.png`): cypress, moss and the Curfew glow. A strong silhouette.
- **Forward+** (`fwd/plaza_night.png`) adds real fog depth and softer light. It's the better look for a desktop build, at 3.5× the draws.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| V1 | High | `scripts/wet_materials.gd`, `scripts/city.gd` road materials | **Carried over from R2.** Medium and High asphalt and pavements are still white per-pixel glitter (`qa_r3/nat_views/medium_quarter_st.png`, `high_velvet.png` median). Very Low is clean, so it's the wet-specular path. | Roughness ≥0.3 on asphalt. Normal strength ≤0.3. Kill the sparkle noise above Medium or mip-bias it. Use the staged `cracked_asphalt` set with its own roughness map. | S | 0 |
| V2 | High | `scripts/hunt/hunt_fx.gd` / `atmosphere.gd` (Curfew wall and boss grade) | **Every boss arena is a red-and-pink wash** (`sheet_bosses.jpg`). The Curfew band, a red sky tint and pink floor light make Marcus's crimson coat and the Knight's red veins disappear into the background. | Tint only the sky and the wall. Keep the arena floor and the characters in neutral moonlight. Drop the wall's emissive by 50% inside the boss state. | S | 0 |
| V3 | High | `scripts/map/velvet.gd`, `city.gd` deco blocks | **Carried over from R2 (V2).** By day the Velvet Mile is grey slab towers with white-square windows. Neon is now a few thin strips (`high_velvet.png`). No marquee, canopies or warm windows, unlike `03_velvet_mile.jpg`. | Lit marquee canopies on the ground floors, cornice bands, sparse warm windows, and banner cards on the lamps. One fan marquee prop (5 credits) or build it procedurally. | M | 0–5 |
| V4 | Med | Night readability: `player.gd` / `atmosphere.gd` | Sol is a black cut-out at night and backlit (`qa_r3/sheet_sol.jpg`, `fwd/plaza_night.png`, where he disappears entirely). **Owned by the QA-fix agent (QA3 #10).** | A moon rim light parented to the camera that lights only Sol's layer, plus fill light in the crypt. | S | 0 |
| V5 | Med | Weapon Art VFX: `items/arsenal.gd` `_nova_fx`, `_wave_node` | **Silver Nova blows out a third of the screen as a flat white disc** (`web/desktop_04_art.png`). The other Arts are nearly invisible, a thin trail plus the move's name in the centre (`sheet_arts.jpg`). Elden Ring Arts read through shape, colour and light, not a label. | Per-Art meshes: a crescent wave (katana), a ground crack ring with debris (hammer), a red vortex ribbon (scythe), a chain arc (whip). Use additive alpha with HDR capped at 1.5, no full-screen bloom disc, and drop the name label. | M | 0 |
| V6 | Med | `scripts/map/docks.gd` | **Carried over from R2 (V3).** The Pier Six deploy is a flat brown expanse with a few pilings (`web/desktop_01.png`). | Container stacks with the rusted texture, sodium floods, a crane silhouette, and wet planks with puddles. | M | 0 |
| V7 | Low | Forward+ budget | `fwd/plaza_night.png`: 1,034 draws and 1.05M primitives (Compatibility on High: 299 / 337k). | Only matters for a desktop build (see Ceiling). Its own LOD and shadow distance. | M | 0 |

## 2. Characters and animation — 6.5 / 10 (R2: 5.5)

**What's good**
- **Marcus Crane is a character now** (`nat/boss_marcus_portrait.png`): his own tall, pale model in a crimson-lined frock coat, with his own lunge and 4-hit combo, and no veins or bubble. The biggest single gain since R2.
- **The Abomination** (`boss_abomination_portrait_b.png`) is a 2.8 m bespoke creature with clawed feet, a slam and a roar.
- **Sol's locomotion:**
  - a relaxed idle with both arms down (`sol_day_idle_front.png`);
  - a real stroll (`sol_day_walk_0..5`);
  - a low crouch creep from the bought clips (`sol_day_crouch_walk_*`);
  - the blade drawn from the back on attack and re-sheathed after 9 s (`sol_day_draw_*`, `sol_day_resheathed_back.png`).
- **The face close-up** (`sol_day_face.png`) holds up in daylight: beard, round shades, coat and strap. The R2 neck smear and grey boots are fixed.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| C1 | High | `scripts/hunt/deploy.gd` | **Sol T-poses through every Descent** (`web/desktop_02.png`, `desktop_03_walk.png` on the rooftop deploy; QA3 #2 on the trail and the boat). It's the first image of every Hunt. **Owned by the QA-fix agent.** | Tick the anim during the Descent with walk (trail, boat) or jump/fall (rooftop, manhole). | S | 0 |
| C2 | High | `items/arsenal_moves.gd`, `items/weapon_forge.gd` | **The 9 weapon types are re-timed sword clips on procedural meshes.** The halberd thrusts with `thrust` (a sword clip), the scythe and the halberd share `axe_sweep`, and the whip has no lash motion. The katana is a thin rod with a red grip (`nat/art_katana_2.png`). In Elden Ring a weapon class *is* its moveset and silhouette. | (a) Buy 6 library clips that suit the types (see Credits). (b) Model 4 hero weapons (katana, greatsword, halberd, scythe) as real meshes: a Meshy text-to-3D prop at about 5 credits each, or a better procedural forge with a fuller, guard, wrap and bevel. (c) A two-handed grip IK for the polearms and the greatsword (left hand on the haft). | M–L | 48 + 20 |
| C3 | High | `hunt/bosses/hollow_alpha.gd`, `blood_knight.gd`, `abomination.gd`, `boss_base.gd` | **The lava-vein overlay and the pink shield bubble are still on the Alpha, the Knight and the Abomination** (`sheet_bosses.jpg`). R2 C1 asked for the bubble only during intro invulnerability. | Show the aura only while `intro_t > 0`. Veins off on the Alpha (darker fur and eye glow instead). The Knight gets an emissive mask from his albedo, not the overlay. | S | 0 |
| C4 | Med | `enemy.gd` hit rim shader (`FX_SHADER`, `rim`) | **The hit read is a flat, solid orange body** for several frames (`sheet_arts.jpg`, every dummy). `r / max(a, 0.001)` saturates the rim to full albedo. It's R2's white flash in orange. | Clamp the rim to a fresnel band (`pow(1 - NdotV, 3)`), at most 0.6 mix, for 60 ms. | S | 0 |
| C5 | Med | Faces | Still no blinks or jaw movement on Sol, Nia, Marcus or Silas when they speak. | A jaw flap from voice amplitude, plus random blinks. | M | 0 |
| C6 | Med | Scanned head | `USE_SCANNED_HEAD := false`. The cleanup stage from R2 §2 exists, but the A/B gate never ran. | Finish steps (a)–(f) and the ±30° re-capture. | M | 1 |
| C7 | Low | Common enemies | Still 3 bodies. | Tint and accessory variants for the elites. | M | 0 |

## 3. Combat and feel — 7 / 10 (R2: 6)

**What's good (from code and smoke)**
- **Stamina** (`player.gd:110`): per-move cost, exhaustion, recovery.
- **Lock-on** (Q / MMB / the touch LOCK button) with strafe and twist (`sol_strafe.gd`).
- **Frenzy now costs:** blood drain, more damage taken, no parry, no bite.
- **Common enemies telegraph with the body** (no decals). Boss decals are faint and colour-blind aware.
- **Arsenal depth:** bleed and hemorrhage, poise and stagger, affinities, special combo routes (sprint, dash, after a parry), plunges, Blood Rite synergies.
- **The R2 bugs are gone:** the boss-fight parry, the charged double hit.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| G1 | High | Weapon identity (C2) | **Up close the arsenal is one sword in nine skins.** Range, speed and poise numbers differ, but the motion and silhouette barely do. This is the gap between "9 weapon types" and "Nightreign weapons". | C2, plus per-type swing SFX (heavy whoosh, chain rattle, polearm thrust). | M | (C2) |
| G2 | Med | Art feedback (V5) | An Art should be the biggest moment of a fight. It reads as a HUD word plus a bloom. | V5, plus a 120 ms hit-stop and camera kick on the Art's strike, and a unique SFX per Art. | M | 0 |
| G3 | Med | Boss move sets (`hunt/bosses/*.gd`) | Marcus has his combo and lunge, and the Abomination its slam and roar. The Alpha and the Knight still share the generic dash, slam, swipe and bolt logic. No delayed swings punish panic rolls. | One delayed-swing variant per boss, the Alpha's pounce plus summon roar, and the Knight's riposte stance. | M | 0 |
| G4 | Med | No dodge-roll | The dash is a Blood Dash blink. Elden Ring's roll, with its i-frames and commitment, is missing as a verb. That's fine for identity, but the dash has no animation of its own. | `Run_Jump_and_Roll` (459) or `Backflip_inplace` (601) as the dash body motion and the back-step. | S | 8 |
| G5 | Low | Feel at speed | Never judged on a real GPU, in any round. | One owner or real-device session with a short checklist: input latency, hit-stop, camera at lock-on. | S | 0 |

## 4. Loop and level design — 7 / 10 (R2: 6.5)

**What's good**
- **The Blood Rite** after each boss: 3 offers, one tuned to the carried weapon (`qa_r3/nat_views/blood_rite.png`).
- **Seeded night modifiers:** Blood Moon, Hunting Party, Ashen Sky.
- **Micro-POIs** on the map legend.
- **The Undercroft Depths:** a duel with Silas Crowe, an elite tithe and a kill record. This is Nightreign's "optional lethal encounter".
- **The graveyard** with Old Amos, longer streets, and a 3-boss pool plus a fixed Final Night.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| L1 | High | Traversal (R2 L3) | Still no vault, climb or rooftops (`11_rooftops.jpg`). Nightreign's map is about vertical routes and shortcuts. | A sprint-vault onto ledges up to 1.2 m, using `Parkour_Vault_with_Roll_inplace` (651). Two Quarter blocks with walkable roofs, joined by a "blood leap". | M–L | 8 |
| L2 | Med | Docks and Velvet Mile (R2 L2) | Still flat corridors with POIs as markers. | Container-top cache routes. A club-basement micro-dungeon (`09_blood_den.jpg`) as a second Undercroft-style interior. | M | 0 |
| L3 | Low | Lair hub | **In progress** (lair agent): walkable hub plus a wardrobe with stat bonuses. | Score next round. Make sure the wardrobe stats feed `stat()` like the Rites do. | — | — |

## 5. Audio — 7.5 / 10 (R2: 6.5)

**What's good**
- **Web audio works:** silent until a gesture, then menu, Hunt and phone all play (QA3 RMS numbers), guarded by CI.
- **A theme per boss** plus a rival duel theme and a shared field-boss theme, in one coherent vampire-hunter hip-hop and industrial style. Loudness is consistent (-11.9 to -13.7 LUFS integrated).
- **Creature SFX** are timed to the new clips.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| A1 | High | `assets/audio/music/boss_*.ogg`, `rival_crowe.ogg` | **Every boss theme is 29–33 s** (ffprobe). A 3-minute boss fight hears the same loop 6+ times. The 38 s length was set by the budget left at the time (`docs/assets_r4/LEDGER.md`). **And nobody has listened to them.** | The owner listens first. Then regenerate the 4 night-boss themes and the rival theme at 120 s with the same prompts (7.68 credits each, quoted). Optionally add a phase-2 intensity layer: `audio.gd` crossfades to a second stem below 50% HP. | S | 38.4 |
| A2 | Med | `audio/audio.gd` (crypt context) | The crypt is near silent (RMS 0.00006). **Owned by the QA-fix agent (QA3 #9).** | A drip and drone bed, and the rival theme when he engages. | S | 0 |
| A3 | Med | `data/dialogue.json` | Still no boss phase-change lines and no pre-fight exchange (R2 A3, S1). | 10–14 lines: a taunt and a phase line per boss, plus Sol's replies. | S | ~3.5 |
| A4 | Low | Weapon SFX | All 9 types swing with the same sword SFX. | 4 swing families (blade, heavy, polearm, chain) from the existing hits, pitched and layered with ffmpeg. | S | 0 |

## 6. UI/UX — 6.5 / 10 (R2: 6)

**What's good**
- **The Options panel:** 5 tabs, fits 720p and the phone, opens from the menu and from pause, with live presets.
- **The Blood Rite card layout,** the ART button with its cooldown ring, and the crouch and walk prompts.
- The Coat and Vigil remain the most Elden-Ring-like screens.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| U1 | High | `ui/inventory_ui.gd` | **The Coat soft-locks the phone** (QA3 #1). **Owned by the QA-fix agent.** | Fit the panel to the viewport and add a ✕ button. | S | 0 |
| U2 | High | `hud.gd` announce, `hunt/hunt_story.gd` card, `items/arsenal.gd` Art label, the boss title | **No message queue (R2 U1, still open).** In one frame (`nat/art_katana_2.png`): "DAY 1 / The Curfew falls at dusk", "BLOOD MARKET CLEARED" and "HEMORRHAGE", all centred over Sol. At the boss intro, the night card, the boss name, the boss subtitle and the boss bar stack (`sheet_bosses.jpg`). | One queue, one slot each: the centre for one big line at a time, the top-left for the night card (4 s, then collapse; QA3 #5), and the bottom for the boss name. Status words like HEMORRHAGE go over the enemy as a small world label. | S–M | 0 |
| U3 | Med | `hud.gd` key-hint strip vs the boss bar | **The boss health bar is drawn over the key-hint strip** ("SPAC…" is cut, `boss_marcus_portrait.png`). | Hide the key strip in the boss state, or once its 30 s fade has passed. | S | 0 |
| U4 | Med | `hud.gd` (R2 U2) | The HUD is still all words: BLOOD, HUNGER, DAYWALKER (sunlight heals you), DASH 3/3, RANK, TITHE, REVIVES, Bosses slain, Sites cleared, Kills. | Bars without labels, dash pips, Tithe bottom-right, and the counters only on the map or pause screen. | M | 0 |
| U5 | Med | `ui/map_screen.gd` (R2 U3) | Still flat coloured rectangles (`qa_r3/web_e/e05_map.png`). It's also the most expensive frame (QA3 #8, owned by the QA-fix agent for the draws). | One `_draw()` canvas over a baked top-down parchment texture. That fixes the look and the draws together, so coordinate with the QA-fix agent. | M | 0 |
| U6 | Low | `hunt/poi_dressing.gd` | The mirrored, floating "HOLLOW PINES" sign. **QA-fix agent (QA3 #3).** | — | S | 0 |

## 7. Story and presentation — 6 / 10 (R2: 6)

**What's good:** Silas Crowe as a pale rival daywalker is the strongest new story hook. The night cards still give each hunt a motive, and the menu lair still sets the tone (the lair hub will replace the text hub).

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| S1 | High | `boss_base.gd`, `hunt_director._spawn_boss` | **No pre-fight beat** (R2 S1, never built). The boss name appears over a gameplay camera, and the fight starts. | 4–6 s: a camera cut to the boss (roar or idle clip), one taunt, Sol's reply, then the bar. Marcus and the Abomination have the clips for it now. | M | (A3) |
| S2 | Med | Seraphine | Still never on screen. | A rooftop silhouette over the Final arena with red eyes, plus 2 lines. | S–M | 0 |
| S3 | Med | Meta | Still no case files, and wins add nothing to the story. | A case file per boss kill in the lair hub (a natural fit for the lair agent's work: a board in the hub). | S | 1.5 |
| S4 | Med | Silas Crowe | A great hook with no follow-up: one duel, a name plate. | 3 lines before the duel, 1 after. His kill record unlocks a lair-hub item. | S | ~1 |

## 8. Code — 6.5 / 10 (R2: 6)

**Good:**
- `smoke_test.gd` PASS with 355 checks plus `arsenal_checks.gd`.
- A frame-budget guard, a CI audio guard and a benchmark (`bench.gd`).
- A clean settings API (`settings.gd` presets, `HFx.opt` hooks).
- Dead assets deleted.
- 12 `class_name`s.

| # | Sev | Where | Evidence | Fix | Effort |
|---|---|---|---|---|---|
| K1 | Med | `scripts/city.gd` | **4,148 lines** (R2: 3,943). The split from R1 and R2 has never happened. | `city/materials.gd`, `batcher.gd`, `quarter.gd`, `props_place.gd`. No behaviour change; smoke guards it. | M |
| K2 | Med | Whole codebase | 404 `.get()` / `has_method` calls (R2: 154 counted more narrowly), and 20 untyped `main` / `director` fields left. | Type the cross-script calls in `player.gd`, `enemy.gd` and `arsenal.gd` first. | M |
| K3 | Low | Engine errors | `Lambda capture at index 0 was freed` ×8 in smoke, and 6,734 `Parameter "m" is null` headless (QA3 #16). | Bind tweens to their node (`create_tween()` on the node itself), and guard the null mesh in the headless path. | S |
| K4 | Low | `bench.gd:374` | Reports the project's renderer, not the running one (QA3 #15). | `RenderingServer.get_current_rendering_method()`. | S |

## 9. Web and performance — 6 / 10 (R2: 5)

**Good:**
- Gameplay views at 107–295 draws and 108–335k primitives from Very Low to Medium (R2: 500–1,000 draws, 1.0–1.4M).
- Auto-detect picks Medium on desktop and Low on the phone.
- Dynamic resolution and pre-warm.
- My boss arena captures on Medium: 187–220 draws and 305–430k primitives (R2: 800+ and 1.2M+).

| # | Sev | Where | Evidence | Fix | Effort |
|---|---|---|---|---|---|
| W1 | High | Download | **`index-143d4d6da0.pck` is 50,877,690 bytes** (R2: 42 MB), plus 8.1 MB of gzipped wasm. The music is only 5.9 MB on disk, so the growth is meshes and textures. **The QA-fix agent owns the audit (QA3 #4).** | Audit with an export listing. Textures to 512 px except hero and ground. Lazy-load the boss bodies and themes at dusk with `load_threaded_request`. Target ≤40 MB. | M |
| W2 | Med | `web/shell.html` | No service worker: every visit downloads 59 MB (R2 W2, D-group item never done). | Cache the `.pck` and wasm by hashed name. | S |
| W3 | Med | Map view | 341–542 draws (QA3 #8). **QA-fix agent.** | See U5. | S–M |
| W4 | Med | Very Low tier | Saves only 10–30 draws over Low (QA3 #8). | Shorter HLOD on Very Low, no undergrowth, and street clutter at 15%. | S |
| W5 | Med | Never on a real phone | Every number is SwiftShader or llvmpipe. | One real mid-range Android (Chrome remote debugging) with `?bench`. The owner can run it and paste the `BENCH_RESULT` line. | S |

## 10. Overall — 6.5 / 10 (R2: 6)

R3 is the round where the systems arrived: a build loop, an arsenal, stamina and lock-on, real boss bodies, music, a settings menu, and a phone-sized frame budget.

What keeps it at 6.5 is the polish between the systems:
- the first shot of every Hunt is a T-pose;
- text piles up in the centre of the screen;
- weapons look and move alike;
- bosses fight inside a red haze and a pink bubble;
- the download is 59 MB.

None of these is hard, and most are S or M. A round spent on polish rather than features is worth +0.5 to +1 overall.

---

## Round 4 fix plan

### Already covered (don't duplicate)
- **The QA-fix agent owns the QA3 top 10:**
  - #1 Coat on the phone (U1);
  - #2 the Descent T-pose (C1);
  - #3 the Hollow Pines sign (U6);
  - #4 the `.pck` audit (W1);
  - #8 the map draws (W3);
  - #7 Rite overflow;
  - #5 the night card collapse (part of U2);
  - #6 touch buttons over the map;
  - #9 the crypt ambience (A2);
  - #10 Sol's rim light and crypt fill (V4).
- **The lair agent owns** the walkable hub and the wardrobe. S3's case-file board and S4's Silas unlock are natural add-ons for it once the hub stands.

### Group F — Weapon identity and Arts (agent 1)
**Files:** `scripts/items/arsenal*.gd`, `weapon_forge.gd`, `weapon_visual.gd`, `tools/build_sol_modular.gd`, `assets/characters/sol/*`, `scripts/sol_draw_ik.gd`, `assets/audio/sfx/swing_*`.

1. **C2:** buy and cut the 6 clips (Credits §1). Re-map each type's chain so no two types share a primary clip. Add a two-handed grip IK for the polearms, greatsword and hammer. *(Characters +0.5, Combat +0.5.)*
2. **V5 + G2:** per-Art VFX meshes, capped HDR (no white disc), Art hit-stop and camera kick, no centre label. *(Combat +0.25, Visuals +0.25.)*
3. **C2b:** 4 hero weapon meshes (forge upgrade, or 4 Meshy props). *(Characters +0.25.)*
4. **A4:** 4 swing SFX families. *(Audio +0.25.)*

### Group G — Bosses and presentation (agent 2)
**Files:** `scripts/hunt/bosses/*.gd`, `boss_base.gd`, `scripts/enemy.gd` (hit rim only), `data/dialogue.json`, `assets/audio/voice/*`, `assets/audio/music/*`.

1. **C3:** the bubble only during the intro, and no veins on the Alpha, Knight or Abomination. **C4:** the hit rim as a fresnel band. *(Characters +0.5.)*
2. **S1 + A3:** the pre-fight beat and phase lines for 4 bosses. **S4:** Silas's lines. *(Story +0.5, Audio +0.25.)*
3. **G3:** a delayed swing per boss, and the Alpha's pounce plus summon. *(Combat +0.25.)*
4. **A1:** after the owner listens, 120 s themes and a phase-2 layer. *(Audio +0.5.)*
5. **S2:** Seraphine's silhouette on the Final Night. *(Story +0.25.)*

### Group H — World polish (agent 3)
**Files:** `scripts/wet_materials.gd`, `city.gd` (plus the K1 split), `scripts/map/velvet.gd`, `docks.gd`, `scripts/atmosphere.gd`, `scripts/hunt/hunt_fx.gd` (Curfew wall only).

1. **V1:** the glitter asphalt (third time listed; small fix). *(Visuals +0.25.)*
2. **V2:** no red wash in the arenas. *(Visuals +0.25.)*
3. **V3 + V6:** Velvet marquees and canopies, the Docks containers and floods. *(Visuals +0.25, Loop +0.25.)*
4. **K1:** split `city.gd` while it's open. *(Code +0.5.)*
5. **W4:** Very Low thinning. *(Web +0.25.)*

### Group I — HUD and messaging (agent 4; after the QA-fix agent merges its night-card and map work)
**Files:** `scripts/hud.gd`, `scripts/ui/*` (except `inventory_ui.gd` while the QA-fix agent has it), `scripts/hunt/hunt_story.gd`, `web/shell.html`.

1. **U2:** one message queue with three slots, and status words moved to world labels. *(UI +0.5.)*
2. **U3:** the key strip vs the boss bar. **U4:** the HUD diet. *(UI +0.5.)*
3. **U5:** the parchment map canvas. Coordinate with the QA-fix agent's map draw fix, or take it over. *(UI +0.25.)*
4. **W2:** a service-worker cache. *(Web +0.25.)*

### Group J — Traversal (agent 5, optional, L)
**Files:** `scripts/player.gd` (vault state), `scripts/sol_locomotion.gd`, two Quarter blocks in `city.gd` (sequence with Group H).

1. **L1:** sprint-vault with the bought clip, walkable roofs on 2 blocks, and the blood leap. *(Loop +0.5, Combat +0.25.)*

**Expected after round 4, if F–I land with the QA-fix and lair work:**

| Visuals | Chars/Anim | Combat | Loop | Audio | UI | Story | Code | Web | Overall |
|---|---|---|---|---|---|---|---|---|---|
| 6.5 | 7–7.5 | 7.5–8 | 7.5 (with the lair) | 8 | 7.5 | 6.5–7 | 7 | 6.5–7 | 7 |

---

## Credits: the highest-value spends

Balance: **142.62** (checked). The prices are the quotes or ledger prices below. Rigging and animation is 8 credits per clip on Sol's body (`docs/animation_reference/README.md`). Music is quoted at 7.68 credits for 120 s on `elevenlabs_music_v2`.

| Priority | Spend | What it buys | Cost |
|---|---|---|---|
| 1 | **6 library clips for weapon identity** on Sol's body (`3d_rigging` with `enable_animation`, 8 each): `Charged_Axe_Chop` (237) for the greatsword and hammer heavy; `Double_Combo_Attack` (92) for the katana chain; `Two_Handed_Parry` (149) for the heavy-weapon parry; `Sword_Parry_Backward` (148) for the guard-break recoil; `Backflip_inplace` (601) for the back-step and the Art recovery; `Run_Jump_and_Roll` (459) as the dash body motion. Check the previews first; the library has no spear or whip attacks, so the halberd and whip keep re-cut clips, with the forge and IK doing the rest. | Combat and Characters: the biggest feel-per-credit gain left | **48** |
| 2 | **Boss themes at 120 s**: Marcus, Abomination, Knight, Alpha, plus the rival. Only after the owner has listened to the current 30 s versions and approved the style. | Ends the 6× loop repetition in every boss fight | **38.40** (5 × 7.68) |
| 3 | **Vault clip** `Parkour_Vault_with_Roll_inplace` (651) | Unlocks traversal (L1) | **8** |
| 4 | **Voice lines**: 14 pre-fight and phase lines plus 4 for Silas | Story S1 and S4, Audio A3 | about **4.5** (preflight; R2's estimate was 0.25 per line) |
| 5 | **Sol ±30° re-capture** for the scanned head | Characters C6 | **1** |
| 6 | **4 hero weapon meshes** (Meshy text-to-3D props, about 5 each; preflight) | The weapon silhouette (C2b). Skip it if the forge upgrade looks good enough. | about **20** |

**Recommended now: priorities 1, 3, 4 and 5 (61.5 credits), and 2 after the listening test (38.4). Total about 100, leaving about 42.** Keep that reserve for retakes and for the lair agent's wardrobe (clothing variants may need a model or two).

Don't spend on Seedance or video clips (they only give 2D video), or on new enemy models before the weapon clips.

---

## Ceiling vs Elden Ring (updated)

The stack is the same as in R2: Godot 4.3 on the WebGL2 Compatibility renderer, AI meshes, library mocap, AI voices and music, single-threaded wasm and a phone target. R3 shows the systems ceiling is higher than R2 assumed. The art ceiling hasn't moved.

| Category | Realistic max on this stack | R3 | What stops it | What would raise it |
|---|---|---|---|---|
| Visuals | **7** (7.5 native Forward+) | 6 | No GI, volumetrics or SSR on WebGL2. The phone triangle budget. AI textures with baked light. | A native desktop Forward+ build (the plaza shot already shows the gain). Hand-placed light per POI. |
| Characters and animation | **7.5** | 6.5 | No facial rig. The library has no spear, whip or polearm sets, so paired moves are faked. | The scanned-head pipeline with ARKit blendshapes. A paid mocap session for about 20 weapon-class moves. |
| Combat and feel | **8.5** | 7 | Library coverage for weapon classes and boss moves. Never tuned on real hardware. | The clips above, a real-device tuning pass, per-boss signatures. |
| Loop and level design | **8** | 7 | Hand-made district content and traversal. | Rooftops and vaults, 2 more interiors, the lair hub. |
| Audio | **8** | 7.5 | AI music and voice range. | Longer themes with phase stems, then a human composer for 2 themes. |
| UI/UX | **8.5–9** | 6.5 | Nothing technical. | The queue, the HUD diet, the map. |
| Story and presentation | **7** | 6 | No facial performance means no close-up cinematics. | Pre-fight beats, Seraphine, Silas's arc, case files in the lair. |
| Code | **9** | 6.5 | Nothing. | The splits and the typing. |
| Web and performance | **7.5** | 6 | A 40–50 MB download, single-threaded WebGL2 and phone thermals. | A cache, lazy boss assets, a real-phone bench. |
| **Overall** | **about 7.5–8** | 6.5 | The browser and AI-asset stack. | A native desktop export adds about +0.5 to Visuals and Overall. |

**For the owner:** R3 moved the game from "a playable prototype" to "a real action-roguelite". The next point comes cheaply from polish: the first shot, overlapping text, weapon identity, the boss haze and the download. It doesn't need more features. Elden Ring's look stays out of reach in a phone browser. Its combat language is now within about 1.5 points.
