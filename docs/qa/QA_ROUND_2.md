# QA Round 2: test pass

**Builds tested**
- Web: `0438e80`, exported locally with the Web preset and served over HTTP.
- Native (deep checks): `0438e80`, plus a re-export of `60fdb8f` (the round 3 staging assets and the coat cloth fix) to measure download size. The coat fix was not re-verified in the browser.

**How it was played**
- **Desktop:** Playwright Chromium (SwiftShader) at 1280×720, keyboard and mouse, `?debug`.
- **Phone:** Pixel 7 emulation (`Pixel 7 landscape`, hasTouch, DPR 2.625) with CDP touch events on the on-screen controls. Portrait shows the shell's rotate overlay by design, so gameplay was tested in landscape.
- **Native probes:** temporary probe scripts (now deleted) drove a Hunt headless for logic and under xvfb for screenshots and draw counts. They used `debug_skip_to`, the seeds that select each deploy point and boss, and InputEventAction presses.
- **Smoke test:** `tests/smoke_test.gd` **PASS** on `0438e80`.

**Evidence**
- All screenshots are in `/tmp/claude-0/-home-user-daywalker/dd1b8b5c-f35a-5096-ac5f-5ff9b687f52e/scratchpad/qa_r2/` (written below as `qa_r2/…`).
- Contact sheets: `sheet_desk1.jpg`, `sheet_desk2.jpg`, `sheet_phone.jpg`, `sheet_phone2.jpg`, `sheet_combat.jpg`.
- Probe logs: `nat_*.log`.
- Browser console logs: `desk_run.log`, `desk2_run.log`, `phone_run.log`, `phone2_run.log`.

**Caveat:** software rendering runs at about 1 fps (`?debug` read "fps 1" throughout), so the browser fps numbers are meaningless. Draw-call and primitive counts are real and are reported instead. Audio can't be heard here; voice was checked through `Dialogue.line_started` and the on-screen subtitles.

## Summary

| Area | Result |
|---|---|
| Loading → menu | Pass. Menu up in under 40 s on SwiftShader. The progress bar was not captured: the first frame arrived with the menu already up. |
| Menu, Sol and Nia, banter | Pass. Banter starts after the first click and about 9 s idle, with coloured subtitles (`sheet_desk1.jpg`). |
| Options | **Issues.** Values apply and persist across a reload (brightness, quality, rain). The panel overflows 720 px and the Back button is cut off (#11). |
| Controls screen | Pass |
| Pause | **Issues.** It works in play, but Esc during the intro opens it over the intro (#3). |
| Hub | **Issues.** Wearing a charm works (mouse). Only 5 of 10 contacts are visible and the list doesn't scroll (#6). On the phone the panel bottom is clipped (#14). |
| First-Hunt intro | **Issues.** Space / STRIKE skip it. Esc opens pause instead of skipping, and Tab opens the Coat underneath it (#3). Touch buttons draw over it (#13). |
| Descent (all 8 points, 6 types) | Pass. Sol lands on the ground and gets control at every point; skipping works. Two points face an obstacle (#15). |
| Terrain, hills, lake | Pass. Climbed to the 24.5 m summit without sticking. A 12,096-point floor raycast found no holes. Wading in the lake is shallow, then an invisible wall stops Sol (#19). **But** the navmesh exists inside the tanks and nothing catches a fall out of the world (#5). |
| Camps idle → aggro | Pass (smoke test plus probes) |
| Combat moves | Pass, with these issues: parry breaks in boss fights (#1); the charged slash double-hits (#10); lunges and leaps rarely fire (#7); the camera is occluded or clips (#8). |
| Loot, Coat, blade swap | Pass. The beam prompt picks the item up, equipping swaps the sword mesh in hand, and the vial stacks into quick-use. |
| Chapel rank-up and Vows, merchant | Pass. Rank 1→2 cost 25 Tithe and gave the Vow "ashmaker"; the merchant sold a vial for 30. |
| Curfew, map, compass | Pass. Outside the wall costs about 9 HP/s with the red tint. The map works on desktop and phone (#12 overlap). |
| Night bosses (Alpha, Marcus, Knight) and the Abomination | Pass, with these issues: every attack type was observed, plus the enrage, death and 2 Eclipse drops. The Knight is silent (#9). Parry errors (#1). |
| Field bosses (3) | Pass. They engage, die, clear their site and pay out. |
| Revive, death drop, recovery, results, return to hub | Pass |
| Phone touch controls | Pass, with these issues: the stick moves Sol; STRIKE skips the intro and Descent; the MAP and COAT buttons open their screens. The night card covers the stick (#12). |
| Performance and size | **Issues.** 139–795 draws (native web tier) and up to 1,034 draws / 1.09M primitives on the web at the Docks. The `.pck` doubles at `60fdb8f` (#2, #4). |
| Console | **Issues.** Every Hunt load logs a navmesh sync error and an agent_radius warning (#18). |

**Counts:** 0 blockers · 7 major · 6 minor · 7 polish, plus one test-gap note (#21).

## Issues

### 1. MAJOR: parry throws a script error in every boss and field-boss fight, and can't parry the adds either
- **Steps:** start any Hunt and reach a boss (night boss, field boss or the Abomination). Press parry (C / middle mouse / L3 / PARRY button) while the boss is alive, for example during its wind-up with a summoned wolf or vampire nearby.
- **Expected:** the parry window runs, and an enemy winding up in reach is parried.
- **Actual:** `SCRIPT ERROR: Invalid access to property or key 'windup_t' on a base object of type 'CharacterBody3D (hollow_alpha.gd)'`, at `_combat_tick (player.gd:819)`, logged 19 times in one press (once per frame of the 0.3 s window). The loop aborts when it reaches the boss, so an add that comes after the boss in `enemies_root` is never parried. `_stagger_enemy` also writes `e.windup_t` and would error on a boss.
- **Evidence:** `qa_r2/nat_boss_parry.log`
- **Suspected cause:** `player.gd:_combat_tick` parry loop and `_stagger_enemy`. `boss_base.gd` has no `windup_t` / `attack_range`. Guard with `"windup_t" in e`, or give bosses the field.

### 2. MAJOR: `60fdb8f` ships `game/assets_staging` inside the web `.pck` (42.0 MB → 81.3 MB)
- **Steps:** at `60fdb8f`, run `--import` and then `--export-release "Web"`.
- **Expected:** staged, unwired assets stay out of the build.
- **Actual:** `index.pck` is 81,307,584 bytes, against 41,997,872 at `0438e80`. It contains 239 `res://assets_staging/...` paths (boss music, SFX, textures). That nearly doubles the phone download; the pck barely compresses (gzip 40.9 MB at 42 MB).
- **Evidence:** `qa_r2/web60/index.pck`; `grep -a assets_staging` on it.
- **Suspected cause:** `game/export_presets.cfg`. `exclude_filter` lacks `assets_staging/*`, and `export_filter="all_resources"` picks up everything imported.

### 3. MAJOR: Esc during the first-Hunt intro opens the pause menu over the intro instead of skipping it; Tab opens the Coat under it
- **Steps:** use a fresh save (new browser profile). Start → Begin the Hunt. While the "THE ACCORD IS BROKEN" case-file card shows, press Esc. Separately, press Tab.
- **Expected:** the on-screen hint says "Attack / Jump / Esc — skip", so Esc should skip the intro, and other menus should stay closed during it.
- **Actual:** "PAUSED" with Resume / Options / Controls / Quit to Menu draws on top of the intro card; the two sets of text overlap. Tab opens THE COAT behind the title card.
- **Evidence:** `qa_r2/intro_esc_pause.png` (the same image as `desk/d13_options_bottom.png`) and `qa_r2/desk2/e06_intro_tab.png`
- **Suspected cause:** `hunt_story.gd:_unhandled_input` loses to `pause_menu.gd:_unhandled_input` and `main.gd:_unhandled_input`, because the Story node sits earlier in the tree. Use `_input` in the story, or have `main.menu_open()` / the pause menu check `hunt.state == "intro"`.

### 4. MAJOR: draw calls and primitives are still 2–5× the phone budget in every district
- **Steps:** use native gl_compatibility (the same "web" render tier) and stand at points across the map, facing two directions, by day and by night. In the browser, use `?debug`.
- **Actual (native):**

  | District | Draws | Primitives |
  |---|---|---|
  | Quarter | 324–551 | 0.67–1.03M |
  | Velvet | 275–671 | 0.57–1.28M |
  | Docks | 139–572 | 0.35–0.99M |
  | Pines | 177–795 | 0.45–1.21M |
  | Bayou | 247–609 | 0.69–0.97M |

  **Actual (web overlay):** Tank Farm 172–494 draws and 412–859k primitives (`desk2/e08`, `e09`). Docks with the map open: 1,034 draws and 1,092k primitives (`phone2/q04_map.png`).
  **Download:** `.pck` 42.0 MB plus about 8.0 MB gzipped wasm. JS heap at the menu: 54 MB (the wasm heap was not measured).
- **Evidence:** `qa_r2/nat_perf.log`, `nat/perf_*.png`
- **Suspected cause:** `city.gd` batching, the tree and impostor ranges in `map/trees.gd`, and the terrain splat / undergrowth (W2 is still open).

### 5. MAJOR: the navmesh is baked inside closed colliders (the Docks tank farm), so nav-snapped placement can drop Sol inside a tank, he falls out of the world, and nothing recovers him
- **Steps:**
  1. `NavigationServer3D.map_get_closest_point` near (-100, 0, 150) returns (-100, 0.5, 150). That point is inside a 10 m tall tank collider; the `Trunks` body, top at y = 10, covers ±4 m.
  2. Place Sol there, which `hunt_director._revive()` does with that same call when a revive lands near the tanks.
- **Expected:** Sol is placed on walkable ground outside the solid; if anything ever falls below the world, it is respawned.
- **Actual:** Sol fell to y = −53 within 2 s and keeps falling: no death, no respawn, a soft-lock. Wolves spawned there fell the same way. My leap test "launched" 4/4 wolves this way.
- **Evidence:** `qa_r2/nat_holes.log` (column dump: `Trunks` at y 10 over `Terrain` at y 0; "Sol dropped … y now −53.4") and `qa_r2/nat_leap.log`
- **Suspected cause:**
  - The `main.gd:_bake_navigation` source geometry. Cylinder colliders (`city.gd:post_collider`) are closed meshes, so Recast walks their bottom cap.
  - `hunt_director._revive` / `debug_view_camp` snap to the navmesh.
  - There is no kill plane anywhere (`grep` finds no `y <` guard in player or enemy). A bad spawn on any other solid would have the same result.
- **Suggested fix:** add a kill-Y respawn to the nearest road point, plus a navmesh obstruction or a `NavigationObstacle3D` for the tanks.

### 6. MAJOR: the hub's "Nia's contacts" shows 5 of 10 charms for sale, and the list does not scroll
- **Steps:** Start → the Undercroft, then mouse-wheel over the contacts list.
- **Expected:** all 10 buyable charms (`hunt_config.gd ARMOURY_SHOP`: 12 minus the 2 free ones) can be reached.
- **Actual:** only Graveyard Salt, Iron Rosary, Pack Fang, Noon Medal and Thorn Rosary are visible. Knucklebones, Gambler's Dice, Mirror Shard, Vigil Candle and Black Candle are clipped below the panel, and the wheel does nothing (desktop and phone).
- **Evidence:** `qa_r2/desk2/e04_hub_scrolled.png`, `qa_r2/phone/p02_hub.png`
- **Suspected cause:** `hunt/hub_panel.gd` shop list. It needs a `ScrollContainer` (or two columns). Not checked: whether keyboard focus can reach the hidden rows.

### 7. MINOR: the new enemy second attacks (vampire lunge, wolf leap) almost never fire in a normal fight
- **Steps:** at night, spawn a vampire 6 m from Sol and stand still for 8 s. Repeat at 5 locations. Then kite (step back 5 m every 2 s) for 20 s.
- **Expected:** players regularly see the lunge's red line telegraph and the leap ring.
- **Actual:**
  - Standing still: **0 lunges** in 5×8 s. The vampire closes from 6 m to 1.5 m in about 0.4 s, before its initial `special_cd` (about 2 s) runs out, then only swipes.
  - Kiting: 1–2 lunges per 20 s.
  - Wolves: 1 leap in 5×10 s.
- **Evidence:** `qa_r2/nat_combat2.log`
- **Suspected cause:** `enemy.gd` `_start_special` gating (the `special_cd` start value, the min 3.5 m band, and that it needs the attack token). Consider a 0 initial cooldown, or picking the special as the opener from range.

### 8. MAJOR: the camera is occluded by street furniture and clips into enemies at melee range
- **Steps:** stand on the plaza's east edge, around (6.7, 0, 30), facing −Z, and fight a dummy. Then parry a vampire at 1.3 m.
- **Expected:** Sol and the target are framed.
- **Actual:** during the combo, charged slash, execution, bite and stagger, a dark awning or wall and a lamp post fill most of the frame, and Sol isn't visible (`sheet_combat.jpg` panels 1–5). On the parry, the camera sits inside the vampire's body (a flat beige / blue blur, panel 6). The critic's G4 is only partly fixed. Sol's position was set by the probe, but it is an ordinary walkable street spot.
- **Evidence:** `qa_r2/sheet_combat.jpg`, `nat/c_combo2.png`, `nat/c_execution_mid.png`, `nat/c_parry.png`
- **Suspected cause:** the `player.gd` camera spring. `CAM_RADIUS` and the collision mask don't cover awning and lamp props, there's no occluder fade, and enemies aren't excluded or faded at under 1.5 m.

### 9. MINOR: Cassius Vane, the Blood Knight, is silent: no intro or death line
- **Steps:** reach the boss with a seed whose Night-1 boss is `knight`.
- **Expected:** an intro line on spawn and a death line on the kill, like the other bosses.
- **Actual:** no line played (`lines:` in the log has no `court_taunt_3`). His intro borrows `court_taunt_3`, a priority-1 bark, which is dropped when any comms line is on the channel. His `death` is `""`.
- **Evidence:** `qa_r2/nat_boss_knight.log`; for comparison, `nat_boss_alpha.log` and `nat_boss_marcus.log` play intro and death.
- **Suspected cause:** `hunt_config.gd NIGHT_BOSS_POOL` (the knight) and `data/dialogue.json`. Give the intro priority 3, or play it with a forced priority.

### 10. MINOR: the charged slash also lands the first light hit
- **Steps:** hold attack on a dummy until the charged slash comes out.
- **Expected:** one heavy hit.
- **Actual:** a 16.1 light hit at frame 227, then the 45.08 charged hit at frame 282. The press starts `light1`, and `_special("charged")` flushes its pending strike.
- **Evidence:** `qa_r2/nat_combat_h.log` ("charged: … hits [[227, 16.1], [282, 45.08]]")
- **Suspected cause:** `player.gd:_attack_pressed`, `_combat_tick` and `_special` (`_flush_pending`). Drop the pending light strike when it becomes a charge.

### 11. MINOR: the Options panel is taller than 720 px; Back is cut off, and V-Sync shows on the web
- **Steps:** at 1280×720, open Options (menu or pause).
- **Expected:** the whole panel fits.
- **Actual:** the top border touches y = 0, and the Back button is half off-screen (only Esc works by mouse-less means). The V-Sync row is listed in the browser, where `settings.gd` deliberately ignores it.
- **Evidence:** `qa_r2/desk/d16_options_after_reload.png`, `qa_r2/desk2/e02_options_after_reload.png`
- **Suspected cause:** `menu/options_panel.gd` row heights (16 rows × 31 px plus headers). Use two columns or a ScrollContainer, and hide V-Sync on the web.

### 12. MINOR: the "TONIGHT YOU HUNT" night card overlaps the DAY announcement, covers the phone's virtual stick and shows through the map
- **Steps:** after the Descent, read the night card.
- **Actual:**
  - On desktop, the card covers "The Curfew falls at dusk. Hunt fast." (`desk2/e09`).
  - On Pixel 7, it sits exactly over the stick zone in the bottom-left (`phone/p05_hunt.png`, `phone2/q01`–`q03`).
  - With the map open, the card and debug text bleed through the map (`phone2/q04_map.png`).
- **Suspected cause:** `hunt/hunt_story.gd:night_card` placement and layer. Move it top-centre under the compass, and hide it while the map is open.

### 13. MINOR: touch controls draw over the first-Hunt intro
- **Steps:** on Pixel 7 landscape, start your first Hunt.
- **Actual:** the stick and all 9 buttons draw over the title card (`phone/p03_intro.png`). The STRIKE tap does skip the intro, but it looks like gameplay has started.
- **Suspected cause:** `ui/touch_controls.gd:_in_play` should treat `hunt.state == "intro"` as not in play, or show only a skip button.

### 14. POLISH: on the phone, the hub panel's bottom edge is clipped and the footer hint shows behind it
- **Evidence:** `qa_r2/phone/p02_hub.png`. The panel runs past the screen bottom, and "Esc back" is half hidden behind it. A hint about Esc means nothing on a phone.
- **Suspected cause:** `hunt/hub_panel.gd` and `menu/main_menu.gd` hint (show the touch hint on touch devices).

### 15. POLISH: two deploy points leave Sol facing an obstacle
- **Steps:** use the seeds that select Velvet Mile Station (subway) or Riverside Drain (manhole), then walk forward for 3 s after the Descent.
- **Actual:** Sol covers 13.0 m and 11.8 m, against 22.3 m at the other six points, because he is blocked.
- **Evidence:** `qa_r2/nat_dep4.log`, `nat_dep6.log`
- **Suspected cause:** the `map/map_layout.gd DEPLOY_POINTS` `face` vectors.

### 16. POLISH: the field boss name renders as "Old Gristle Of The Pines" in the compass and site label
- **Evidence:** `qa_r2/phone/p05_hunt.png` (compass), `nat_field.log`
- **Suspected cause:** POI `display_name` built with `capitalize()`. Keep the casing from `hunt_config.gd FIELD_BOSSES`.

### 17. POLISH: generic "VAMPIRE" street taunts play during the Abomination fight
- **Evidence:** `qa_r2/nat_boss_abomination.log` ("vamp_taunt_2: The Count wants you alive. Mostly.", during the final boss).
- **Suspected cause:** `audio.gd:enemy_bark` reacting to the boss's Court rider. Skip barks for `boss_base` bodies.

### 18. POLISH: console noise on every Hunt load
- **Web, phone and native:**
  - `USER ERROR: Navigation map synchronization error. Attempted to merge a navigation mesh polygon edge with another already-merged edge…` (`nav_map.cpp:990`)
  - `USER WARNING: Property agent_radius is ceiled to cell_size voxel units`
- **Headless:** more than 1,400 `ERROR: Parameter "m" is null` per run (the critic's K5).
- **Evidence:** `desk2_run.log`, `phone_run.log`, `nat_*.log`
- **Suspected cause:** `main.gd:_bake_navigation` (agent_radius 0.5 against cell 0.3, and overlapping colliders); mesh queries under the dummy renderer.

### 19. POLISH: lake wading stops at an invisible wall without feedback
- **Steps:** walk into the lake (centre (64, −207), radius 23, water level 14) from three sides.
- **Actual:** Sol wades to 0.7 m below the surface (y 13.3), then stops dead 15–20 m from the centre. There's no splash, slowdown or prompt.
- **Evidence:** lake probe output, quoted in this section (from 3 directions: "…20:13.3/13.3" repeated).
- **Suspected cause:** `map/terrain.gd` lake wall collider. Add a slow-wade zone or a visible shoreline cue.

### 20. POLISH: the keyboard hint strip stays on screen for the whole Hunt
- **Evidence:** `desk2/e08`–`e10`. "WASD move · SHIFT sprint · SPACE jump (x2) · LMB combo…" stays bottom-left (the critic's U4 is only partly done).
- **Suspected cause:** `hud.gd` bottom-left hints. Fade them after the first minute.

### 21. POLISH: a test gap, not a bug
These were not verified this round:
- Hunt Again from the results screen in a browser.
- The loading progress bar: the first screenshot arrives after the menu.
- Gamepad.
- Sol's coat and neck seam close-ups.
- Audio levels, which can't be heard here.

## Top 10 to fix next (by player impact)
1. **#1** Parry breaks in every boss fight (script error, adds can't be parried).
2. **#2** Exclude `assets_staging` from the export: the download doubles to 81 MB.
3. **#5** Kill-plane respawn, plus keep nav snaps out of the tank colliders (fall-through soft-lock).
4. **#8** Camera occluded by street props and inside enemies at melee range.
5. **#4** Draw calls and primitives: 300–1,000 draws and about 1M primitives, far over a phone budget.
6. **#3** Esc / Tab during the first-Hunt intro open the pause menu or Coat over it.
7. **#6** Hub shop list clipped: half the meta charms can't be bought.
8. **#12** The night card covers the phone stick and the announcement text.
9. **#7** Make the lunge and leap actually appear (cooldown and band gating).
10. **#11** Options panel overflows 720 px (Back off-screen); hide V-Sync on the web.

## Passed (solid)
**Front end**
- The menu renders.
- Nia and Sol banter starts after the first click and about 9 s idle, with speaker-coloured subtitles.
- The Controls screen is complete.
- Options brightness, quality and rain apply and **persist across a page reload** in the browser.
- Wearing a hub charm works by mouse (it shows [WORN] and appears in the loadout).
- Begin the Hunt by mouse: HUNT_READY 54 s later on SwiftShader.

**Intro, Descent and controls**
- The intro skips with Space, and with the STRIKE tap on the phone.
- The Descent skips with Space and STRIKE.
- All **8 deploy points (ladder, manhole ×2, trail, boat, subway ×2, rooftop)** land Sol on the ground, with the camera handed over and walking possible.
- Pointer lock engages on the first click in play.
- WASD and mouse look work. Touch: the stick moves Sol, and the MAP and COAT buttons open their screens.

**Combat**

| Move | Result |
|---|---|
| 3-hit combo | Strike lands 8 physics frames (0.13 s) after the press; 16.1 / 16.1 / 32.2 damage |
| Charged slash | Staggers |
| Dash thrust from 6 m | 25.8 |
| Sprint slash at 13 m/s | 20.9 |
| Execution | Kills, with the victim reaction |
| Bite | Heals about 41, and hunger rises |
| Parry vs swipe | Staggers |
| Heavy-blade combo (Bayou Butcher) | heavy1 / 2 / 3 for 24.6 / 24.6 / 72.6 |

- Acceleration takes 5 frames and stopping 8 frames, so the run ramps instead of starting dead.
- Health bars show over engaged enemies.

**Run systems**
- A loot beam's prompt lets Sol take the item. Equipping a blade **swaps the sword mesh in hand**. Vials stack into quick-use.
- The Coat opens and pauses (desktop and phone).
- Chapel vigil: rank 1→2 for 25 Tithe and a Vow pick.
- Merchant purchase.
- Curfew shrink and damage (about 9 HP/s, red tint), and the phase label.
- The map on desktop and phone.

**Bosses**
- **Hollow Alpha:** swipe, howl, slam.
- **Marcus:** blink, swipe, dash, bolts.
- **Knight:** swipe, dash, slam, plus bolts in phase 2.
- **Abomination:** all 7 attack types in phase 2.
- Every one spawns on the Curfew close, enrages below half, dies, and drops 2 Eclipse items.
- Intro and death voice play for the Alpha, Marcus and Seraphine.
- Field bosses (Aurelien, Corvina, Old Gristle) engage, die and clear their Landmark.

**Death and results**
- A revive at half blood, half the Tithe dropped and recovered by walking back, and a second death ends the run.
- The results screen (epilogue, Sunmarks) and Return to the Undercroft.

**Terrain**
- Hills are climbable to the 24.5 m summit without sticking.
- A 12,096-point floor raycast grid found no holes.
- No falls in a 40-spot random-run sweep.
- Lake shallows are wadeable.

**Smoke test** PASS.
