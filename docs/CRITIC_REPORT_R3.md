# DAYWALKER: Blood and Moon — Critic Report, Round 3

Reviewed: commit `143d4d6` (branch `claude/day-walker-game-concept-mz8vvv`, deployed as `index-143d4d6da0.pck`), 2026-11-26.
No game code was changed.

**Evidence** is under `/tmp/claude-0/-home-user-daywalker/dd1b8b5c-f35a-5096-ac5f-5ff9b687f52e/scratchpad/critic_r3/`:
- `nat/`: native Compatibility captures.
- `fwd/`: one Forward+ view through lavapipe.
- `web/`: the deployed build in Playwright.
- Contact sheets: `sheet_bosses.jpg`, `sheet_sol_a.jpg`, `sheet_sol_b.jpg`, `sheet_arts.jpg`, `sheet_web.jpg`.

I also used the QA round 3 evidence (`scratchpad/qa_r3/`) for the tier views, the Undercroft and the settings.

## The bar (set by the owner for this round)

| Area | Categories | Compared with |
|---|---|---|
| Realism and atmosphere | Visuals, Characters (look), Story and presentation | **Until Dawn**: photoreal faces and performance capture, cinematic framing, volumetric horror lighting. |
| Animation and action movement | Characters (animation), Combat (feel) | **The Blade films**: aggressive, fluid two-handed sword work, kicks, acrobatic martial-arts flair. |
| Gameplay and features | Loop, Combat (systems), UI | **Elden Ring Nightreign**: a compact roguelite map, a shrinking ring, relics and build choices, class kits, map events, boss nights. |

**Platform:** the game is headed for **Steam** (desktop, with mouse and keyboard and gamepad). Touch controls are being removed, so phone touch UI is not scored. Web and phone performance still count for testing, but desktop counts more.

**In progress, noted and not scored:** the walkable lair hub and the wardrobe with clothing stat bonuses (another agent).

## Score table

The "old bar" column is how R3 scores against R2's general "Elden Ring" bar, to show real progress. **The R3 score is against the owner's new bar** and goes into the score history. The new bar is harsher on realism and presentation (Until Dawn) and on movement flair (Blade). It is kinder to performance now that desktop is the target.

| # | Category | R2 | R3 (old bar) | **R3** | One-line reason (against the new bar) |
|---|---|---|---|---|---|
| 1 | Visuals | 5.5 | 6 | **5.5** | **Up:** the plaza on High, the graveyard, crows and the candle-lit crypt have real atmosphere. **Still down:** Until Dawn is photoreal, volumetric and close-framed. Here the asphalt glitters, the Velvet Mile is grey slabs, the boss arenas drown in Curfew red, and Sol is a black shape at night. Forward+ (the Steam path) is the moodier look and isn't the default. |
| 2 | Characters and animation | 5.5 | 6.5 | **5.5** | **Up:** Marcus and the Abomination are real bodies. Sol walks, crouches and draws from his back. **Still down:** against Blade, Sol fights one-handed with library sword clips: no kicks, no two-handed grip, no acrobatics. He T-poses through every Descent. Against Until Dawn, there's no face animation at all. Three bosses still wear lava veins and a pink bubble. |
| 3 | Combat and feel | 6 | 7 | **6.5** | **Systems (Nightreign) are about 7.5:** lock-on, stamina, a Frenzy that costs, body telegraphs, 9 weapon types, Arts, combo routes, bleed and poise, the Blood Rite. **Movement (Blade) is about 5:** weapons are re-timed sword clips, Arts read as a label plus a white bloom, and the hit read is a flat orange body. No kicks, no aerial moves. |
| 4 | Loop and level design | 6.5 | 7 | **6.5** | **Up:** the Blood Rite, night modifiers, micro-POIs, the Undercroft rival duel, longer streets. **Still down:** Nightreign has class kits, map events, traversal (spirit springs, climbing) and enterable structures. Here there's one character, no traversal, no enterable buildings (the bayou plantation house is a solid facade), and flat Docks and Velvet Mile corridors. |
| 5 | Audio | 6.5 | 7.5 | **7** | **Up:** web audio is fixed, every boss and the rival have a hip-hop or industrial theme, and the creature SFX are wired. **Still down:** the themes are 29–33 s loops (6+ repeats per fight) that nobody has heard yet. Sol's voice (preset "Brooks") is too soft for the owner's deep, menacing action-hero brief. The crypt is silent. |
| 6 | UI/UX (desktop) | 6 | 6.5 | **6.5** | **Up:** the 5-tab settings panel is excellent, and the Rite card is clean. **Still down:** Nightreign's HUD is minimal, but here text stacks in the centre (DAY 1, SITE CLEARED, Art names, the night card over the boss intro). The HUD is all words, the map is a schematic, the boss bar covers the key strip, and there are no gamepad button glyphs. |
| 7 | Story and presentation | 6 | 6 | **5** | Against Until Dawn's cinematic, performance-captured storytelling, nothing on screen is staged. Bosses never speak before the fight, Seraphine is never seen, there are no cutscenes and no faces move. Silas Crowe is the one good new hook. |
| 8 | Code | 6 | 6.5 | **6.5** | **Up:** 355 smoke checks, a CI audio guard, a clean settings API, 12 `class_name`s. **Still down:** `city.gd` grew to 4,148 lines, there are 404 `.get()` / `has_method` calls, and engine errors remain. There's no Steam export path yet. |
| 9 | Web and performance | 5 | 6 | **6.5** | **Up:** gameplay views are down to 107–295 draws, with tiers, dynamic resolution and pre-warm. That's easily fine on a desktop GPU. **Still down:** Forward+ costs 1,034 draws on the plaza with no budget of its own. There's no desktop export preset, the web `.pck` is 50.9 MB, and nothing has been measured on real hardware. |
| 10 | **Overall** | 6 | 6.5 | **6** | A real action-roguelite with the right systems. Against Until Dawn's presentation and Blade's choreography, the gaps are faces and cinematics, kicks and two-handed flair, and the polish layer: the first-shot T-pose, stacked text, the red haze. |

### Owner's playtest complaints: status

| Complaint | Status at `143d4d6` | Evidence |
|---|---|---|
| Frame rate | **Much better.** Draws are down 2–4×, with tiers, dynamic resolution and pre-warm. Forward+ (the desktop look) needs its own budget. Not measured on real hardware. | QA3 #8, `fwd/plaza_night.png` |
| No sound | **Fixed.** | QA3 |
| Undercroft stairs and a rival | **Done.** The crypt is silent and dark (QA3 #9, #10). | `qa_r3/sheet_undercroft.jpg` |
| Sword on his back | **Done.** Scabbard, draw and sheathe IK, per-weapon mounts. | `nat/sol_day_idle_back.png`, `sol_day_resheathed_back.png` |
| Short streets | **Lengthened.** | — |
| Graveyard look and crows | **Done.** | `qa_r3/nat_views/medium_cemetery.png` |
| More weapons, moves, combos | **9 types, Arts and routes are in.** But most types re-cut the same ~12 one-handed sword clips on procedural meshes. | `sheet_arts.jpg`, `arsenal_moves.gd` |
| Settings for weak devices | **Done and good.** | `qa_r3/web_a/a02–a06` |
| Real walk, crouch, arm at idle | **Done** with the bought clips. A calm stroll and a low creep. | `nat/sol_day_walk_*`, `sol_day_crouch_*` |
| Blade-style hip-hop boss music | **In and wired**, six themes. **Not listened to yet.** 29–33 s loops. | `assets/audio/music/` |
| **New:** a more aggressive voice for Sol | **Open.** Sol is Higgsfield preset "Brooks" on `elevenlabs_v4` (24 lines). See A2 and Credits. | `assets/audio/CREDITS.md` |
| **New:** two-handed swings and kicks | **Open.** None exist. See C2, G1 and Credits. | — |
| **New:** enter the bayou plantation house, loot inside | **Open.** `wilds.gd:_plantation` places `plantation_facade.glb` as a solid prop. See L2. | `scripts/map/wilds.gd:498` |
| Lair hub with a wardrobe | **In progress** (another agent). Not scored. | — |

### R2 fix groups: what landed

| R2 group | Landed | Still open |
|---|---|---|
| **A, asset integration** | Creature clips, Marcus and Abomination bodies (decimated to about 17k), Marcus without veins or bubble, the Alpha at 1.35×, boss themes, creature SFX, props and texture library. | The boss **pre-fight beat** (S1). The **Alpha, Knight and Abomination still wear the vein overlay and the shield bubble** (`sheet_bosses.jpg`). |
| **B, combat and Sol** | Body telegraphs, lock-on, Frenzy cost and stamina, neck, boots and hem fixes, blood spray and hit-stop, sheath mounts. | The **hit rim saturates into a flat orange body**. The **scanned head** is still off. |
| **C, world and budget** | Frame budget, HLOD, plaza oaks, Velvet neon strips, graveyard and mausoleum, the wadeable lake. | **Glitter asphalt** (third report running), Velvet facades, Docks, **red arena wash**, splitting `city.gd`. |
| **D, UI, story, audio, shell** | Per-boss music switching. | **Nearly all of it:** the message queue, the HUD diet, the parchment map, case files, Seraphine, the cache. |
| **E, loop and code** | Blood Rite, modifiers, micro-POIs, dead assets removed, `class_name`s, `skip_to` boss in the arena, the web navmesh errors. | The navmesh bake at import. |

## How this was reviewed

**Native captures:**
- Compatibility under xvfb, 1280×720, Medium and High, seed 4242, with a temporary capture script (deleted).
- What was captured:
  - Sol close up: 4 angles, face, walk ×6, run ×4, crouch idle and walk, draw ×6, drawn and re-sheathed.
  - 7 weapon Arts × 5 frames.
  - All 4 night bosses in the arena: gameplay camera and portrait.
  - The plaza on High.
- **Forward+:** one plaza view on High through lavapipe.

**Web:**
- The deployed `143d4d6` build in Playwright Chromium (SwiftShader), desktop 1280×720 and Pixel 7 landscape.
- HUNT_READY at 94 s and 112 s. The console was clean.
- **Download:** `.pck` 50,877,690 bytes, wasm 8.1 MB gzipped.

**Also:**
- QA round 3's sheets and tables, and the code paths cited.
- Music length and loudness with ffprobe and ebur128.
- Higgsfield cost quotes for music and voice.

**Limits:**
- Software rendering runs at about 1 fps, so **feel and timing are judged from code and frame sequences, not from play at speed.** No round has had a real-GPU pass yet.
- My boss captures swap tonight's boss in by script, so the night card in those frames names Marcus over other bosses. That part is an artefact. The stacking itself is real.

---

## 1. Visuals — 5.5 / 10 (against Until Dawn)

**What's good**
- **The plaza on High** (`nat/plaza_night.png`): the cathedral and rose window down a street of iron galleries, moss and sedans. The closest frame yet to `01_plaza_night.jpg` and `12_old_quarter_avenue.jpg`.
- **The graveyard** (`qa_r3/nat_views/medium_cemetery.png`, `medium_shed.png`): varied headstones, obelisks, fencing, a shed with a lit window, and crows. It finally has a horror mood.
- **The crypt** (`qa_r3/sheet_undercroft.jpg`): candle clusters and warm stone. The most Until-Dawn-like space in the game.
- **Forward+** (`fwd/plaza_night.png`): real fog depth and softer light. That's the look a Steam build should ship with.

**What Until Dawn has that this doesn't:**
- volumetric light shafts and fog that catches torchlight;
- close, low, cinematic camera framing;
- photoreal skin and cloth;
- deep blacks with a readable silhouette rim on the character.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| V1 | High | Renderer for Steam: `project.godot`, `scripts/settings.gd`, `export_presets.cfg` | The desktop target can use **Forward+**: volumetric fog, SSAO, SSR, glow and soft shadows (`fwd/plaza_night.png` already looks moodier). Today Forward+ is just the project default, with no tier of its own and 1,034 draws on the plaza. | A **desktop Forward+ export preset**. Settings tiers that switch volumetric fog (density 0.02–0.04, light shafts from the lamps and the rose window), SSAO, SSR on wet ground and glow. Its own LOD and shadow budget (target ≤1,500 draws on a GTX 1060). Keep Compatibility for the web test build. | M | 0 |
| V2 | High | `scripts/wet_materials.gd`, `city.gd` road materials | **Carried over twice.** The asphalt and pavements on Medium and High still glitter white per pixel (`qa_r3/nat_views/medium_quarter_st.png`, `high_velvet.png`). | Roughness ≥0.3, normal ≤0.3, no sparkle noise. On Forward+, let SSR do the wet look instead. | S | 0 |
| V3 | High | `hunt/hunt_fx.gd` / `atmosphere.gd` | **Every boss arena is a red-and-pink wash** (`sheet_bosses.jpg`). Marcus's crimson coat and the Knight's veins vanish into it. | Tint only the sky and the Curfew wall. Keep the floor and characters in cold moonlight. Cut the wall's emissive by 50% during the boss state. | S | 0 |
| V4 | High | Character lighting: `player.gd`, `atmosphere.gd` | Sol is a black cut-out at night (`qa_r3/sheet_sol.jpg`) and disappears in Forward+ (`fwd/plaza_night.png`). Until Dawn always rims its characters. **The QA-fix agent owns the basic rim (QA3 #10).** | Beyond the QA fix: a camera-relative key and rim rig on the character layer, with a slightly warm key from the nearest lamp. | S | 0 |
| V5 | Med | `scripts/map/velvet.gd`, `docks.gd` | The Velvet Mile is grey slabs by day. The Docks deploy is a flat brown plain (`web/desktop_01.png`). | Marquee canopies, sparse warm windows, container stacks with floods. | M | 0 |
| V6 | Med | `items/arsenal.gd` `_nova_fx`, `_wave_node` | **Silver Nova blows out a third of the screen as a white disc** (`web/desktop_04_art.png`). The other Arts are nearly invisible (`sheet_arts.jpg`). | Per-Art meshes with HDR capped at 1.5, and no name label. | M | 0 |

## 2. Characters and animation — 5.5 / 10 (looks against Until Dawn, motion against Blade)

**What's good**
- **Marcus Crane** (`nat/boss_marcus_portrait.png`): his own model in a crimson-lined frock coat, with his own lunge and 4-hit combo. The biggest single gain since R2.
- **The Abomination** (`boss_abomination_portrait_b.png`): a 2.8 m bespoke creature.
- **Sol's locomotion:** a relaxed idle, a real stroll, a low crouch creep, and the blade drawn from the back and re-sheathed with IK (`sheet_sol_a.jpg`, `sheet_sol_b.jpg`).
- **His face in daylight** (`sol_day_face.png`) has a strong identity: beard, round shades, coat.

**Blade comparison:** Blade fights in tight, aggressive bursts:
- a two-handed sword cut;
- a spinning back-kick into a slash;
- a flip over an attacker;
- a stomp finisher.

Sol's library set is a polite one-handed fencing vocabulary: Triple_Combo, Thrust, Charged, Judgment, Left_Slash. None of the Blade verbs exist.

**Deductions**

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| C1 | High | `scripts/hunt/deploy.gd` | **Sol T-poses through every Descent** (`web/desktop_02.png`, `desktop_03_walk.png`, QA3 #2). It's the first image of every Hunt. **QA-fix agent.** | Keep the anim ticking during the Descent. | S | 0 |
| C2 | High | `tools/build_sol_modular.gd`, `sol_draw_ik.gd`, `items/arsenal_moves.gd` | **No two-handed grip.** The Meshy library has almost no two-handed sword attacks (only `Two_Handed_Parry` 149 and the axe and hammer swings Sol already owns). So two-handed work has to come from **IK**: put the left hand on the hilt below the right fist. | (a) A left-hand two-bone IK target on the blade's grip (`GripPoint` + 0.12 m along −Z), blended in for the katana, greatsword, halberd, scythe and hammer, and for a "two-hand stance" toggle on the longsword (Elden Ring's two-handing). (b) Re-time the owned clips for two hands: `charged`, `hammer`, `axe_spin` and `judgment` already read as two-handed once the left hand holds. (c) Buy `Charged_Axe_Chop` (237) and `Two_Handed_Parry` (149). | M | 16 |
| C3 | High | New moves: `items/arsenal_moves.gd`, `sol_moves.gd`, `player.gd` | **No kicks or acrobatics.** The library has a good kick set. | Buy Blade verbs, 8 credits each (see Credits): `Spartan_Kick` (206) as a guard-break push kick, `Lunge_Roundhouse_Kick_inplace` (649) as a combo ender, `Backflip_Sweep_Kick_inplace` (604) as an evade-attack, `Sweeping_Kick` (217) as a knockdown, `Rising_Flying_Kick` (422) as a launcher, and `Run_Jump_and_Roll` (459) as the dodge body. Bind the kick to a new input (F, or the pad's B while locked on). The kick staggers and opens the bite. Weave it into the combo routes ("slash, slash, kick"). | M | 48 |
| C4 | High | `hunt/bosses/hollow_alpha.gd`, `blood_knight.gd`, `abomination.gd`, `boss_base.gd` | **Veins and pink bubble on three bosses** (`sheet_bosses.jpg`). Until Dawn monsters are grounded and real. | Aura only while `intro_t > 0`. No veins on the Alpha. An emissive mask instead of the overlay on the Knight. | S | 0 |
| C5 | High | Faces: `sol_modular_anim.gd`, the Nia, Marcus and Silas rigs | **No face moves.** Until Dawn's whole presentation rests on faces. | Short term: a jaw flap from the voice amplitude plus blinks (about 40 lines per rig). Medium term: switch on the scanned head (C6) and add ARKit-style blendshapes from a phone capture for Sol and Nia. | M (L for blendshapes) | 0–1 |
| C6 | Med | Scanned head | `USE_SCANNED_HEAD := false`. The cleanup stage exists, but the A/B gate never ran. | Finish R2 §2's steps (a)–(f) and the ±30° re-capture. | M | 1 |
| C7 | Med | `enemy.gd` hit rim | **A flat orange body for several frames** (`sheet_arts.jpg`). | A fresnel band (`pow(1 - NdotV, 3)`), at most 0.6 mix, 60 ms. | S | 0 |
| C8 | Med | `items/weapon_forge.gd` | The procedural weapons read as rods (`nat/art_katana_2.png`). | A better forge (fuller, guard, wrap, bevel), or 4 Meshy hero weapons. | M | 0–20 |

## 3. Combat and feel — 6.5 / 10 (systems against Nightreign, motion against Blade)

**Systems, about 7.5 against Nightreign** (from code and smoke):
- **Stamina** with exhaustion; **lock-on** with strafe; **a Frenzy that costs**.
- **Body telegraphs.**
- **The arsenal:** 9 types with Arts, combo routes (sprint, dash, after a parry), bleed and hemorrhage, poise and stagger, affinities.
- **The Blood Rite** with weapon synergies.
- **The parry** works in boss fights.

**Motion, about 5 against Blade:** see C2 and C3. Plus:

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| G1 | High | Combat verbs: `player.gd`, `sol_moves.gd` | Blade's style is close-quarters aggression: kick to break the guard, cut, flip out. The game has attack, heavy, Art, dash and parry, and nothing that mixes in the body. | (a) **A kick** (C3) that breaks poise and chains into the bite or execution. (b) **An aerial**: a jump attack from the existing jump into a `Rising_Flying_Kick` or plunge. (c) **A wall-flip evade** near walls (optional; `Wall_Flip` 450). (d) Contextual **stomp finishers** on downed enemies (re-cut `Sweeping_Kick`). | M | (C3) |
| G2 | High | Weapon identity | The 9 types are mostly re-timed one-handed sword clips (`arsenal_moves.gd`: the halberd thrusts with a sword thrust; the scythe and halberd share `axe_sweep`). | Two-hand IK (C2) for the heavy types, the kicks woven into each type's routes, and per-type swing SFX. | M | (C2) |
| G3 | Med | Art feedback | An Art reads as a HUD word plus a bloom (V6). | Per-Art meshes, a 120 ms hit-stop and camera kick, a unique SFX. | M | 0 |
| G4 | Med | Boss move sets | The Alpha and the Knight still share the generic logic. There are no delayed swings. | A delayed swing per boss, the Alpha's pounce and summon, the Knight's riposte stance. | M | 0 |
| G5 | Med | Gamepad feel (Steam) | Never tested on a pad at real frame rate. There's no rumble. | `Input.start_joy_vibration` on hits, parries and Arts. A real-device feel session with a checklist. | S | 0 |

## 4. Loop and level design — 6.5 / 10 (against Nightreign)

**What's good**
- **The Blood Rite** (pick 1 of 3, tuned to the weapon) and **seeded night modifiers**: this is Nightreign's relic and night-condition idea.
- **Micro-POIs.**
- **The Undercroft duel** with Silas Crowe (Nightreign's "optional lethal encounter").
- **The graveyard,** a 3-boss pool plus a Final Night, the Curfew ring.

**What Nightreign has that this doesn't:**
- 8 classes with distinct kits;
- map events (a meteor, a castle, a shifting earth);
- fast traversal (spirit springs, wall-climbing);
- enterable structures with loot (forts, churches, ruins);
- 3-player co-op.

Co-op is out of scope on this stack. The rest is reachable.

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| L1 | High | Traversal | No vault, climb or rooftops. | A sprint-vault with `Parkour_Vault_with_Roll_inplace` (651). Walkable roofs on 2 Quarter blocks. A "blood leap" between them. | M–L | 8 |
| L2 | High | **The Belle Rive plantation house (owner request)**: `scripts/map/wilds.gd:_plantation`, new `scripts/map/plantation_interior.gd` | It's a solid `plantation_facade.glb` prop on the Drowned Lawn. The owner wants to go inside a two-storey white house and find loot. | **Build it like the Undercroft:** reuse `undercroft.gd`'s `Geo` kit (boxes, beams, shafts, merged per material, ≤40 meshes, ≤8 unshadowed lights).<br>- **Floors:** a ground-floor hall with a **grand double staircase**, a parlour and a dining room; an upper landing with 2–3 bedrooms and a balcony onto the columns.<br>- **Ruin and dressing:** a partly flooded ground floor (the bayou water plane reaches inside), collapsed ceiling holes with moonlight shafts, peeling wallpaper, dust sheets on furniture, a chandelier.<br>- **Loot:** a POI type `"manor"` via `register_poi`, with 3–5 loot coffins and chests (`loot.gd`), one rare-tier guaranteed upstairs, guarded by a vampire nest or a ghoul ambush, plus one locked room that opens after the guard dies.<br>- **Door:** cut the doorway into the facade (or replace the facade with a procedural shell matched to it) and add a `contains()` check for the interior grade and ambience, as `undercroft.gd` does.<br>- **Mood:** Until Dawn in miniature. Creaking SFX, lightning flashes through the windows, a candle path. | L | 0 (optional: chandelier and 4-poster bed props, about 10) |
| L3 | Med | Docks and Velvet Mile | Flat corridors. | Container-top caches, and a club-basement interior (`09_blood_den.jpg`) using the same interior kit as L2. | M | 0 |
| L4 | Med | Map events | Every night is the same structure plus a modifier. | One roaming map event per Hunt (Nightreign style): a "Blood Moon procession" convoy to ambush, or a burning church to loot before it collapses. Reuse POI and site APIs. | M | 0 |
| L5 | Low | Lair hub | **In progress** (lair agent). | Make sure the wardrobe stats feed `stat()` like the Rites do. | — | — |

## 5. Audio — 7 / 10

**What's good:**
- **Web audio is fixed.**
- **A coherent hip-hop and industrial theme per boss and the rival,** at consistent loudness (-11.9 to -13.7 LUFS integrated).
- **Creature SFX** are timed to the clips.

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| A1 | High | `assets/audio/music/boss_*.ogg`, `rival_crowe.ogg` | **Every theme is 29–33 s** (ffprobe), so a 3-minute fight repeats it 6+ times. **No one has listened to them.** | The owner listens first. Then 120 s versions of the 4 night-boss themes (7.68 each, quoted on `elevenlabs_music_v2`), the rival optional, plus a phase-2 crossfade below 50% HP in `audio.gd`. | S | 30.72 (+7.68) |
| A2 | High | **Sol's voice (owner request)**: `assets/audio/voice/*`, `data/dialogue.json`, `assets/audio/CREDITS.md` | Sol is preset **Brooks** on `elevenlabs_v4`, with 24 lines. The owner wants a deep, menacing, gravelly action-hero delivery. | (1) **Audition** 3 deeper male presets with one line each: candidates by name are **Gideon, Knox, Barrett** (also Orion, Bram, Xavier). Use v4 delivery tags such as `[low, gravelly, menacing]` and present the takes to the owner. (2) **Regenerate all 24 Sol lines** with the chosen voice. Re-write the softer ones ("Sounds about right. Did it say thank you?") into clipped threats. (3) **Add combat efforts** (kick grunts, the Art shout, a parry exhale): 10 short lines. (4) Pitch-check against Nia and Marcus so the cast stays distinct. | S | about 18 (0.46 per short line, quoted) |
| A3 | Med | `data/dialogue.json` | No boss phase lines and no pre-fight exchange. | 14 lines: a taunt and a phase line per boss, plus Sol's replies (in the new voice). | S | about 6.5 |
| A4 | Med | `audio/audio.gd` | The crypt is silent. **QA-fix agent (QA3 #9).** | A drip and drone bed. | S | 0 |
| A5 | Low | Weapon and kick SFX | All 9 types share the sword SFX, and kicks would need impact sounds. | 4 swing families plus a body-impact layer, made with ffmpeg from the existing hits. | S | 0 |

## 6. UI/UX (desktop) — 6.5 / 10 (against Nightreign)

**What's good:**
- **The Options panel** (5 tabs, live presets).
- **The Blood Rite card.**
- The Coat and Vigil screens.

Phone touch UI isn't scored (touch is being removed). **The QA3 Coat-on-the-phone blocker becomes moot** once touch goes; the panel should still fit 720p.

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| U1 | High | `hud.gd` announce, `hunt/hunt_story.gd` card, `items/arsenal.gd` Art label, the boss title | **No message queue.** In one frame: "DAY 1 / The Curfew falls at dusk", "BLOOD MARKET CLEARED" and "HEMORRHAGE", all centred over Sol (`nat/art_katana_2.png`). The night card, the boss name and the boss bar stack at the boss intro (`sheet_bosses.jpg`). Nightreign shows one banner at a time. | One queue with three slots: the centre for one line at a time, the top-left for the night card (4 s, then collapse; QA3 #5), and the bottom for the boss name. Status words become world labels over the enemy. | S–M | 0 |
| U2 | High | Gamepad glyphs (Steam) | Every prompt names keyboard keys ("[E] BITE", "V", the key strip). A Steam Deck or pad player sees the wrong labels. | An input-device detector that swaps glyphs (Xbox and PlayStation sets as textures or font icons) in the HUD, the prompts, Controls and the Rite. Rebinding exists in part. Finish it for the pad. | M | 0 |
| U3 | Med | `hud.gd` | The HUD is all words: BLOOD, HUNGER, DAYWALKER (sunlight heals you), DASH 3/3, RANK, TITHE, REVIVES and 3 counters. The boss bar covers the key strip (`boss_marcus_portrait.png`). | Bars without labels, dash pips, Tithe bottom-right, counters only on the map. Hide the key strip in boss fights. | M | 0 |
| U4 | Med | `ui/map_screen.gd` | Flat rectangles. The most expensive frame (QA3 #8; **QA-fix agent** for the draws). | A baked parchment texture plus one `_draw()` canvas. | M | 0 |
| U5 | Low | `hunt/poi_dressing.gd` | The mirrored "HOLLOW PINES" sign. **QA-fix agent.** | — | S | 0 |

## 7. Story and presentation — 5 / 10 (against Until Dawn)

**What's good:**
- Silas Crowe, a pale rival daywalker, is a strong hook.
- The night cards give every hunt a motive.
- The menu lair sets the tone.

**What Until Dawn has:**
- a cinematic camera for every beat;
- faces that act;
- choices with consequences;
- dread built through pacing.

The game has captions over gameplay.

| # | Sev | Where | Evidence | Fix | Effort | Credits |
|---|---|---|---|---|---|---|
| S1 | High | `boss_base.gd`, `hunt_director._spawn_boss` | **No pre-fight beat** (asked for in R2, never built). | 4–6 s: a letterboxed camera cut to the boss (roar or idle clip), one taunt, Sol's reply in the new voice, then the bar. Marcus and the Abomination have the clips. | M | (A3) |
| S2 | High | Cinematic camera kit: new `scripts/hunt/cine_cam.gd` | There's no reusable staging tool. Until Dawn's look comes from low, close, slow camera moves. | A small rail and look-at camera with letterbox, DoF (Forward+) and a vignette, driven by data (`[{at, look, fov, t}]`). Use it for boss intros, the plantation-house entry, Silas's duel and the epilogue. | M | 0 |
| S3 | Med | Seraphine | Never seen. | A rooftop silhouette over the Final arena, plus 2 lines. | S–M | about 1 |
| S4 | Med | Silas Crowe | One duel and a name plate. | 3 lines before and 1 after. His record unlocks a lair item (lair agent). | S | about 2 |
| S5 | Low | Case files | No narrative reward for wins. | A case file per boss kill on the lair's board (lair agent). | S | about 1.5 |

## 8. Code — 6.5 / 10

**Good:**
- `smoke_test.gd` PASS (355 checks) plus `arsenal_checks.gd`.
- A frame-budget guard, a CI audio guard and `bench.gd`.
- A clean settings API.
- 12 `class_name`s.

| # | Sev | Where | Evidence | Fix | Effort |
|---|---|---|---|---|---|
| K1 | Med | `scripts/city.gd` | **4,148 lines** (R2: 3,943). | Split it into materials, batcher, quarter and props. | M |
| K2 | Med | Whole codebase | 404 `.get()` / `has_method` calls and 20 untyped `main` / `director` fields. | Type `player.gd`, `enemy.gd` and `arsenal.gd` first. | M |
| K3 | Med | **Steam path:** `export_presets.cfg`, a new `scripts/platform/steam.gd` | No Windows or Linux desktop preset, no Steamworks. | Windows and Linux presets (Forward+). GodotSteam (GDExtension) behind a feature flag: init, achievements (3 bosses, Silas, a flawless night), cloud saves for `user://`, rich presence. Save files under `user://` already, so check that the paths are platform-safe. | M |
| K4 | Low | Engine errors | `Lambda capture … was freed` ×8, and 6,734 `"m" is null` (QA3 #16). | Bind tweens to their node, and guard the null mesh. | S |
| K5 | Low | `bench.gd:374` | Reports the wrong renderer (QA3 #15). | `RenderingServer.get_current_rendering_method()`. | S |

## 9. Web and performance — 6.5 / 10 (desktop weighted)

**Good:**
- **Gameplay views:** 107–295 draws and 108–335k primitives from Very Low to Medium (R2: 500–1,000 draws, 1.0–1.4M).
- **Boss arenas** on Medium: 187–220 draws and 305–430k primitives in my captures.
- On any desktop GPU this is light. Auto-detect, dynamic resolution and pre-warm all work.

| # | Sev | Where | Evidence | Fix | Effort |
|---|---|---|---|---|---|
| W1 | High | Desktop Forward+ budget | 1,034 draws and 1.05M primitives on the plaza (`fwd/`). Compatibility on High: 299 / 337k. | A Forward+ tier with its own LOD and shadow distance, and the volumetrics from V1. Bench on a real GTX 1060 / RX 580-class GPU and a Steam Deck. | M |
| W2 | Med | Real hardware | Every number is software rendering. | The owner runs `?bench` (or `--bench` natively) on a desktop GPU and on a phone, and pastes the `BENCH_RESULT` line. | S |
| W3 | Med | Web test build | The `.pck` is 50.9 MB (QA3 #4; **QA-fix agent**). The map is 341–542 draws (QA3 #8; **QA-fix agent**). | As in QA3. It matters less now: the web is for testing. | M |
| W4 | Low | Very Low | Saves only 10–30 draws over Low. | Shorter HLOD on Very Low. | S |

## 10. Overall — 6 / 10

Against R2's bar, R3 earns 6.5. The systems arrived:
- a build loop and an arsenal;
- stamina and lock-on;
- bespoke bosses with music;
- a settings menu and a desktop-friendly frame budget.

Against the owner's sharper bar it's 6, because the two things the new bar measures most aren't there yet:
- **cinematic, face-driven presentation** (Until Dawn);
- **martial-arts body movement** (Blade).

Both are reachable on this stack:
- **Forward+ volumetrics, a cine camera, jaw flaps and boss beats** for the presentation;
- **library kicks and acrobatics plus two-hand IK** for the movement.

Most of the 6 → 7 gap is that, plus the polish layer: the first shot, stacked text, the red haze.

---

## Round 4 fix plan

### Already covered (don't duplicate)
- **The QA-fix agent owns the QA3 top 10:**
  - the Descent T-pose (C1);
  - the Hollow Pines sign (U5);
  - the `.pck` audit and the map draws (W3);
  - Rite overflow;
  - the night-card collapse (part of U1);
  - the crypt ambience (A4);
  - Sol's rim and crypt fill (V4);
  - the touch items (#1, #6), now low priority since touch is being removed.
- **The lair agent owns** the walkable hub and the wardrobe. S4's Silas unlock and S5's case-file board fit there.

### Group F — Blade movement: kicks, two hands, acrobatics (agent 1; the top priority)
**Files:** `tools/build_sol_modular.gd` (CUTS), `assets/characters/sol/*`, `scripts/sol_draw_ik.gd` (left-hand IK), `scripts/sol_moves.gd`, `scripts/items/arsenal_moves.gd`, `arsenal.gd`, `scripts/player.gd` (kick input and aerial only), `assets/audio/sfx/kick_*`, `swing_*`.

1. **C3 + G1:** buy and install the kick and acrobatic clips (Credits §1). Add a kick input. Weave kicks into every type's routes, plus a jump attack and stomp finishers. *(Characters +0.5, Combat +0.5.)*
2. **C2:** left-hand IK for two-handed grips on the heavy types and a two-hand stance toggle. Buy `Charged_Axe_Chop` and `Two_Handed_Parry`. *(Characters +0.5, Combat +0.25.)*
3. **G3 + V6:** per-Art VFX meshes, capped HDR, hit-stop and camera kick. *(Combat +0.25, Visuals +0.25.)*
4. **A5:** swing families and kick impact SFX. **C7:** the fresnel hit rim. *(Combat +0.25.)*

### Group G — Bosses, voice and cinematics (agent 2)
**Files:** `scripts/hunt/bosses/*.gd`, `boss_base.gd`, new `scripts/hunt/cine_cam.gd`, `data/dialogue.json`, `assets/audio/voice/*`, `assets/audio/music/*`, `scripts/audio/audio.gd` (phase layer), `scripts/enemy.gd` (hit rim only, if Group F hasn't taken it).

1. **A2:** audition 3 voices for Sol, get the owner's pick, regenerate 24 lines and add 10 efforts. *(Audio +0.25, Story +0.25.)*
2. **C4:** no bubble or veins outside the intro. *(Characters +0.25.)*
3. **S2 + S1 + A3:** the cine camera kit, the boss pre-fight beats and phase lines. *(Story +1.)*
4. **C5:** jaw flap plus blinks on Sol, Nia, Marcus and Silas. *(Characters +0.25, Story +0.25.)*
5. **A1:** after listening, 120 s themes and a phase-2 layer. *(Audio +0.5.)*
6. **G4, S3:** a delayed swing per boss, and Seraphine's silhouette. *(Combat +0.25, Story +0.25.)*

### Group H — Desktop look and Steam (agent 3)
**Files:** `project.godot`, `export_presets.cfg`, `scripts/settings.gd` (Forward+ tier keys), `scripts/atmosphere.gd`, `scripts/wet_materials.gd`, `scripts/hunt/hunt_fx.gd` (Curfew wall only), new `scripts/platform/steam.gd`.

1. **V1 + W1:** a desktop Forward+ preset with volumetric fog and light shafts, SSAO, SSR and glow, and its own LOD and shadow budget. *(Visuals +0.75, Web +0.25.)*
2. **V2 + V3:** fix the glitter asphalt, and drop the red arena wash. *(Visuals +0.5.)*
3. **K3:** Windows and Linux presets, plus GodotSteam behind a flag (achievements, cloud saves). *(Code +0.25.)*
4. **G5:** gamepad rumble. *(Combat +0.1.)*

### Group I — The plantation house and level interiors (agent 4)
**Files:** new `scripts/map/plantation_interior.gd`, `scripts/map/wilds.gd` (`_plantation` only), `scripts/hunt/poi*.gd` (the `"manor"` type via `register_poi`), `scripts/loot.gd` (a manor table if needed), `tests/smoke_test.gd` (manor checks).

1. **L2:** the enterable two-storey Belle Rive house, with loot, a guard, a locked room, moonlight shafts and storm flashes. *(Loop +0.5, Visuals +0.25, Story +0.25.)*
2. **L3:** a club-basement interior on the same kit. *(Loop +0.25.)*

### Group J — HUD, glyphs and code health (agent 5; after the QA-fix agent merges)
**Files:** `scripts/hud.gd`, `scripts/ui/*` (except files the QA-fix agent holds), `scripts/hunt/hunt_story.gd`, `scripts/city.gd` (the K1 split only; sequence with Group H's `wet_materials` work).

1. **U1:** the message queue. **U3:** the HUD diet and the key strip. *(UI +0.75.)*
2. **U2:** gamepad glyphs and pad rebinding. *(UI +0.25.)*
3. **U4:** the parchment map. *(UI +0.25.)*
4. **K1 + K2 + K4:** split `city.gd`, type the core scripts, fix the engine errors. *(Code +0.5.)*

### Later (L): traversal
**L1:** the vault, rooftops and the blood leap (`player.gd`, `city.gd`). Run it after Groups F and H free those files. *(Loop +0.5.)*

**Expected after round 4 (new bar), if F–J land with the QA-fix and lair work:**

| Visuals | Chars/Anim | Combat | Loop | Audio | UI | Story | Code | Web | Overall |
|---|---|---|---|---|---|---|---|---|---|
| 6.5 | 7 | 7.5 | 7.5 | 7.5–8 | 7.5 | 6.5 | 7 | 7 | 7 |

---

## Credits: the highest-value spends

**Balance: 142.62** (checked with `balance`). The prices are quotes or ledger prices:
- **Library animation clip** on Sol's body (`generate_3d`, `3d_rigging`, `enable_animation`): **8 credits each** (ledger, `docs/animation_reference/README.md`). Check the GIF previews before buying.
- **Music,** `elevenlabs_music_v2`, 120 s: **7.68** (quoted).
- **Voice,** `elevenlabs_v4`, one short line: **0.46** (quoted). Longer lines cost more.

| # | Spend | What it buys | Cost |
|---|---|---|---|
| 1 | **Blade movement pack, 6 clips:** `Spartan_Kick` (206, guard-break push kick), `Lunge_Roundhouse_Kick_inplace` (649, combo ender), `Backflip_Sweep_Kick_inplace` (604, evade-attack), `Charged_Axe_Chop` (237, two-handed overhead), `Two_Handed_Parry` (149), `Run_Jump_and_Roll` (459, dodge body) | Kicks, two-handed weight and acrobatic evasion: the owner's Blade bar. The biggest gain per credit left. | **48** |
| 2 | **Sol's new voice:** audition 3 presets (Gideon, Knox, Barrett) with 1 line each (about 1.4), regenerate 24 lines (about 11), plus 10 combat efforts (about 4.6) | The owner's deep, menacing, gravelly Sol | **about 17** |
| 3 | **Boss and Silas lines in context:** 14 pre-fight and phase lines plus 4 for Silas, about 18 lines | The boss beats (S1) and Silas's arc | **about 8.5** |
| 4 | **Boss themes at 120 s** for the 4 night bosses (after the owner listens and approves the style) | Ends the 6× loop repetition | **30.72** |
| 5 | **Blade movement pack, tier 2:** `Sweeping_Kick` (217, knockdown), `Rising_Flying_Kick` (422, launcher and aerial) | Aerial and knockdown verbs | **16** |
| 6 | **Vault clip** `Parkour_Vault_with_Roll_inplace` (651) | Traversal (L1) | **8** |
| 7 | **Sol ±30° re-capture** for the scanned head | Face realism (C6) | **1** |

**Recommended now: items 1, 2, 3, 5 and 7, about 90.5. Item 4 after the listening test (30.72). Total about 121, leaving about 21.** Keep that reserve for retakes, the vault clip if traversal starts (8), and the lair agent's wardrobe.

**Optional, if credits free up:**
- the rival theme at 120 s (7.68);
- plantation interior props (a chandelier and a 4-poster bed, about 5 each);
- 4 Meshy hero weapons (about 20).

**Don't buy:** Seedance or other video (2D only), or new enemy bodies before the movement pack.

---

## Ceiling (updated for Steam and the new bar)

**What moving to desktop Steam changes:** Forward+ on a desktop GPU lifts the realism ceiling by about +1 over the WebGL2 Compatibility renderer:
- volumetric fog, SSAO, SSR and glow;
- higher triangle and shadow budgets;
- no 50 MB download constraint.

**What doesn't change:**
- AI meshes and textures;
- no performance capture;
- library-only motion;
- AI voices and music.

| Category | Realistic max (desktop Forward+, this pipeline) | R3 | What stops it | What would raise it |
|---|---|---|---|---|
| Visuals (vs Until Dawn) | **7–7.5** | 5.5 | AI textures with baked light, no photogrammetry, no hand lighting pass. | The Forward+ volumetrics tier, a hand-lit pass on the 3 hero spaces (plaza, crypt, plantation house), photoscanned materials. |
| Characters and animation (Until Dawn looks, Blade motion) | **7** | 5.5 | No facial capture. The library has few two-handed or martial-arts sword moves. | The scanned head plus blendshapes from a phone capture. A paid mocap session of 20–30 Blade-style moves (a stunt performer with a sword) is the single biggest lift available. |
| Combat and feel | **8.5** | 6.5 | Motion coverage. Never tuned on real hardware. | The movement pack, two-hand IK, tuning on a pad. |
| Loop and level design (vs Nightreign) | **8** | 6.5 | No co-op (out of scope). Hand-made content. | Interiors, traversal, map events, more character kits (the wardrobe is a start). |
| Audio | **8** | 7 | AI voice range. | The new Sol voice, longer themes, a human actor for Sol later. |
| UI/UX | **8.5–9** | 6.5 | Nothing technical. | The queue, glyphs, the HUD diet, the map. |
| Story and presentation (vs Until Dawn) | **6.5–7** | 5 | No facial performance means no close-up drama. | The cine camera, boss beats, jaw flaps, then blendshape faces. |
| Code | **9** | 6.5 | Nothing. | The splits, the typing, Steam integration. |
| Desktop performance | **8.5** | 6.5 | Nothing hard on desktop. | A Forward+ budget and real benches. |
| **Overall** | **about 7.5–8** | 6 | The AI-asset and library-mocap pipeline. | A mocap session and facial capture are the two investments that move the ceiling, not code. |

**For the owner:** the Steam move is the right call for this bar. Forward+ alone closes about a point of the Until Dawn gap. The Blade bar is mostly an animation problem: 6–8 library clips plus two-hand IK get you kicks and weight. Real Blade choreography needs a mocap session. The Nightreign bar is the closest: the systems are there, and interiors (starting with the plantation house), traversal and map events finish it.
