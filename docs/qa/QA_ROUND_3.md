# QA Round 3: test pass

**Builds tested**
- **Web (deployed GitHub Pages):**
  - `b052634` (`index-b052634….pck`) for the desktop menu, Options and Hunt sessions and the first phone session.
  - `f452aff` (`index-f452affc27.pck`, with the relaxed arm, walk and crouch) for the Undercroft desktop session and the second phone session.
- **Native (`f452aff`):** the Compatibility renderer under xvfb (llvmpipe) at 1280×720. It was used for draw counts per tier, the tier benchmark, and Sol's locomotion stills.
- **Smoke test:** `tests/smoke_test.gd` **PASS** (355 checks) on `b052634`. Coverage includes the Undercroft walk down and up, the Silas Crowe duel and loot, the graveyard and crows, all 9 weapon types and Arts, the special combos, the Blood Rite, the modifiers, the micro-POIs, the presets and the R2 regressions.

**How it was played**
- **Desktop:** Playwright Chromium (SwiftShader) at 1280×720, keyboard and mouse, with Chromium's autoplay policy left on, as a real player has it.
- **Phone:** `Pixel 7 landscape` (863×360 CSS, DPR 2.625, hasTouch), driven with CDP touch events.
- **Native probes:** a temporary probe script and `tests/bench_run.gd`. The probe is deleted.

**Evidence**
- All files are under `/tmp/claude-0/-home-user-daywalker/dd1b8b5c-f35a-5096-ac5f-5ff9b687f52e/scratchpad/qa_r3/`, written below as `qa_r3/…`.
- **Web sessions:**
  - `web_a/`: menu, Options, hub.
  - `web_b/`: desktop Hunt.
  - `web_c/` and `web_e/`: phone.
  - `web_f/`: Undercroft, crouch, walk and pause Options.
  - Each has a `console.txt`.
- **Contact sheets:** `sheet_phone.jpg`, `sheet_phone2.jpg`, `sheet_undercroft.jpg`, `sheet_views_verylow.jpg`, `sheet_views_medium.jpg`, `sheet_sol.jpg`.
- **Native:**
  - `nat_views/*.png` and `nat_views_<tier>.log` for draw counts.
  - `bench_<tier>.json` / `.log`.
  - `nat_sol/` and `nat_sol.log` for locomotion.
  - `smoke.log`.

**Caveat:** software rendering runs at about 1 fps in the browser, so timing and feel can't be judged there. A keypress lasts only a frame or two of game time. Draw and primitive counts, audio RMS, layouts and logic are real.

## Summary

| Area | Result |
|---|---|
| Web audio | **Fixed.** RMS is 0 with a suspended context before any gesture. After the first click: menu 0.014, Hunt 0.022, walking 0.043. Phone after the first tap: 0.019. No bus cycle. The crypt is near silent after the click (minor #9). |
| Loading, pre-warm | Pass. The "Preparing the night..." card shows (`web_b/b00_load.png`), then "CLICK TO TAKE THE HUNT". |
| Settings (5 tabs) | Pass. Graphics / Display / Preferences / Audio / Accessibility, from the main menu (`web_a/a02`–`a06`) and from the pause menu (`web_f/f08`, `f09`). The panel fits 720p with Back visible, and V-Sync is gone on the web. Auto-detect picks **Medium** on desktop web, and `?tier=verylow` forces Very Low. |
| Hub, Nia's Rack | Pass. All 9 types are listed with price and Art, the list scrolls, and the carried blade is marked (`web_a/a08_hub.png`). |
| Combat (desktop) | Pass for what can be seen at 1 fps: the attack draws the sword (`b04`), V fires Silver Nova (`b09`), Q / K / hold attack respond, and Tab is blocked under pause (`b13`, `b14`). Deeper move checks pass natively in the smoke test. |
| Undercroft | Pass. `?autohunt&undercroft` lands in the crypt after the Descent, and SILAS CROWE, THE PALE DAYWALKER shows his name plate (`web_f/f02`). The walk down and up, the duel, the loot and the kill record pass natively. |
| Graveyard | Pass. The shed, open grave, crows and Old Amos all pass smoke. Stills: `nat_views/medium_shed.png`, `medium_grave.png`. |
| Loop | Pass. The Blood Rite opens after Marcus (`nat_views/blood_rite.png`), and the night modifier is on the card and the phase line (Hunting Party, Blood Moon, Ashen Sky seen). Micro-POIs are on the map legend. The Rite card text overflows (#7). |
| Locomotion (`f452aff`) | Pass. Walk toggle 1.10 m/s ("WALKING"). Crouch: capsule 1.30 m, 1.00 m/s ("CROUCHED · enemies notice you later"). Sprint stands him up (13 m/s). The sword re-sheathes after 9 s. In the web, X and Z work (`web_f/f06`, `f07`). |
| Phone | **Blocker:** the Coat can't be closed on a phone (#1). The touch layer, the MAP and COAT buttons, the ART and CROUCH buttons and the night card placement all work. |
| Performance | **Much better than R2.** Native views are 107–295 draws and 108–335k primitives on Very Low to Medium (R2: 139–795 draws, 0.35–1.28M). The Map screen is now the most expensive view (#8). The `.pck` grew to 50.1 MB (#4). |
| Console | Clean. No navmesh or agent_radius errors on the web (R2 #18 is fixed). One `PAGEERROR: A user gesture is required to request Pointer Lock` on Esc-resume (#14). |

**Counts:** 1 blocker · 3 major · 6 minor · 6 polish.

---

## Blockers

### 1. BLOCKER: on a phone, the Coat can't be closed; its button row is below the screen, so the game stays paused
- **Steps:** on a Pixel 7 in landscape, start a Hunt and tap COAT (top right). Then try to leave.
- **Expected:** a Close button (or the COAT button again) returns to play.
- **Actual:**
  - The Coat panel is taller than the phone's viewport, so its Equip / Use / Drop / **Close** / Pause row and the hint line are cut off. The visible panel ends at "Stagger 1.0 · Silver".
  - The touch controls hide while the Coat is open, so the COAT and II buttons are gone.
  - Taps on the panel only select inventory slots. The world stays paused and there is no way back to the game without a keyboard or pad.
- **Evidence:** `qa_r3/web_e/e06_coat.png`, `e07_pause.png`, `e08_pause_options.png` (taps on the old COAT and II positions, then on screen centre: still in the Coat). Contact sheet: `qa_r3/sheet_phone2.jpg`.
- **Suspected cause:** `ui/inventory_ui.gd:46` `panel.custom_minimum_size = Vector2(1220, 600)` plus the button row. The phone's base viewport is about 1288×537 after the phone UI scale. The panel needs to fit, as the Options panel's `fit_scale()` does, or needs a top-corner close (✕) button. Also check that `touch_controls` shows a back or close button while `menu_open()` is true for the Coat. The Blood Rite (900 wide), the level-up (860) and the merchant probably fit, but they were not tapped on the phone.

## Majors

### 2. MAJOR: Sol T-poses through the whole Descent (trail and boat seen; probably every deploy type)
- **Steps:** start a Hunt that deploys at Hollow Pines Trail (desktop, `?autohunt`) or at Bayou Landing (phone), and watch the Descent before "CLICK TO TAKE THE HUNT".
- **Expected:** Sol walks out of the trees or rides in on the skiff, animated.
- **Actual:** Sol slides along the trail in the bind pose, arms straight out sideways (a T-pose), for the whole Descent. He animates normally once play starts. This is the first shot of every Hunt.
- **Evidence:** `qa_r3/web_f/f02_crypt_click.png` (trail, `f452aff`), `qa_r3/web_b/b02_ready.png` (trail, `b052634`), `qa_r3/crop_pose.png`, `qa_r3/crop_pose2.png` (Bayou Landing, phone).
- **Suspected cause:** `hunt/deploy.gd:44` calls `pl.set_physics_process(false)` for the Descent. The modular anim (or its AnimationTree advance and arm and draw IK) is ticked from the player's physics step, so the skeleton falls back to rest. Keep the anim ticking during the Descent with an idle or walk clip (play `walk` for trail and boat, `fall` for rooftop and manhole).

### 3. MAJOR: the "HOLLOW PINES" deploy sign floats in mid-air, mirrored, and overlaps the Descent title
- **Steps:** deploy at Hollow Pines Trail.
- **Actual:**
  - A huge "HOLLOW PINES" Label3D hangs about 2.4 m above the trail marker's root, not on the signboard.
  - From Sol's side it reads **backwards** ("SENIP WOLLOH"), right behind "THE HUNT BEGINS / Hollow Pines Trail" (`web_b/b02`, `b03`, `web_f/f03`).
  - It stays visible over the road at the start of play (`web_b/b06_walk.png`).
- **Evidence:** `qa_r3/web_b/b03_settled.png`, `qa_r3/web_f/f03_toward_rival.png`
- **Suspected cause:** `hunt/poi_dressing.gd:486`, in `label(r, "HOLLOW PINES", …, 2.4)` with billboard disabled. It is placed at the root (0, 2.4, 0) and is double-sided. Put it on the board (about (2.2, 1.8, 0.53) in `r`), shrink it (pixel_size about 0.004), set `double_sided = false` with the face toward the arrival direction, or keep it a billboard.

### 4. MAJOR: the web download grew again, to a 50.1 MB `.pck` (R2: 42.0 MB) plus a 35.4 MB wasm
- **Steps:** `curl -sI https://mygoodvibes24.github.io/daywalker/index-f452affc27.pck`
- **Actual:**
  - `content-length: 50129872`. The pck barely compresses (R2: 40.9 MB gzipped at 42 MB).
  - `index.wasm` is 35,376,909 bytes (about 8 MB gzipped).
  - That's over 58 MB before the Hunt on a phone connection.
  - `assets_staging` is excluded now (R2 #2 is fixed), so the growth is new shipped content: weapons, the crypt, Marcus, the Abomination, boss themes, crows and the walk clip.
- **Suspected cause:** audit with `godot --export-pack` plus a size listing. The boss themes and creature SFX as OGG at high bitrate and the textures of the new models are the likely bulk. Consider lazy-loading boss music and boss models per night (a `ResourceLoader.load_threaded_request` at dusk).

## Minors

### 5. MINOR: the night card still takes a big part of the screen at the start of play
- **Desktop:** top centre, about 500×280 px, over Sol and the road. It stays up through the first stretch of play (`web_b/b09_art.png`, `b11_sheathed_idle.png`). The R2 #12 overlap with the stick and the map is fixed: it hides under the map (`b12_map.png`).
- **Phone:** it sits at the bottom centre between the stick and the buttons, over Sol (`web_c/c07`–`c09`).
- **Fix:** the critic's U6. Show it for about 4 s, then collapse it to a one-line objective under the compass.

### 6. MINOR: on the phone, the touch buttons stay drawn round the open map and cover its legend
- **Evidence:** `qa_r3/web_e/e05_map.png`. With the map open, BITE, RUN, CROUCH, PARRY, DASH and STRIKE draw over the legend's right half.
- **Fix:** hide the action buttons (keep only MAP and II) while the map is open, or move the legend under the map on narrow screens.

### 7. MINOR: Blood Rite card text overflows its card
- **Steps:** kill a night boss (Marcus in the probe).
- **Actual:** card 1's tag "WEAPON ART · SUITS YOUR SILVER LONGS…" is clipped. Its body "Your Weapon Art recharges 40[%] faster and strikes 25% harder" runs past the card's right edge, and the "%" after 40 is lost.
- **Evidence:** `qa_r3/nat_views/blood_rite.png`
- **Suspected cause:** `ui/rite_ui.gd`. The body label needs `autowrap_mode` with a fixed width, and the tag line needs shortening or wrapping.

### 8. MINOR: the Map screen is now the most expensive frame in every tier, and Very Low is barely cheaper than Low
- **Native views (Compatibility, 1280×720):**

  | View | Very Low draws / prims | Low | Medium |
  |---|---|---|---|
  | Plaza (night) | 227 / 157k | 257 / 199k | 295 / 323k |
  | Plaza oaks | 214 / 171k | 225 / 195k | 278 / 334k |
  | Quarter street | 195 / 147k | 206 / 164k | 276 / 304k |
  | Velvet Mile | 124 / 108k | 158 / 149k | 207 / 273k |
  | Docks | 107 / 155k | 118 / 161k | 153 / 311k |
  | Hollow Pines | 135 / 111k | 145 / 167k | 186 / 286k |
  | Lake shore | 133 / 149k | 138 / 187k | 188 / 335k |
  | Cemetery | 130 / 113k | 174 / 173k | 212 / 290k |
  | Shed | 151 / 159k | 165 / 186k | 212 / 331k |
  | Open grave | 149 / 147k | 160 / 183k | 199 / 303k |
  | Crypt (web, Very Low overlay) | 142–153 / 150–170k | — | — |
  | **Map open** | **341** / 127k | **377** / 166k | **415** / 283k |
  | Marcus fight / Blood Rite | — | — | 178 / 360k · 260 / 373k |

  High (stopped after 4 views under llvmpipe): plaza 328 / 364k, plaza oaks 303 / 369k, Quarter street 297 / 331k, Velvet Mile 215 / 284k. High is the only tier over about 300 draws in the city.
- **Benchmark (`bench_<tier>.json`, mean draws per segment):**
  - Very Low: drop-in 208, roam 162, camp 179, boss 165, map 325.
  - Low: 230 / 176 / 205 / 181 / 320.
  - Medium: 296 / 219 / 243 / 219 / 366.
  - High did not finish in 15 min under llvmpipe (1.7–2.7 s frames).
- **Web overlay:**
  - Medium, desktop: 162–246 draws, 221–294k primitives, and 361 with the map open.
  - Phone (Low): 209–324 draws, 140–228k primitives, and 542 draws with the map open (`web_e/e05_map.png`).
- **The good news:** every gameplay view on Very Low to Medium is now inside the 150–300 draws and 300–500k triangles phone budget.
- **The issue:** the map overlay adds 120–220 draws over the world behind it (each icon is a draw). Very Low only saves about 10–30 draws over Low.
- **Suspected cause:** `ui/map_screen.gd`. Draw the icons into one `_draw()` canvas or a cached texture, and stop rendering the 3D world (hide the camera, or render a frozen frame) while the map covers it. For Very Low, merge or cull more static props (HLOD at a shorter range).

### 9. MINOR: the Undercroft crypt is near silent after the unlocking click
- **Steps:** `?autohunt&undercroft`, click once in the crypt, and measure for 5 s.
- **Actual:** peak RMS **0.00006**, against 0.022 on the street after a click. It rises to 0.052 once Sol moves (footsteps). There is no crypt ambience or music until something happens; the duel arena is silent.
- **Evidence:** `qa_r3/web_f/console.txt` (AUDIO lines).
- **Suspected cause:** the `audio.gd` context while `depths.inside` is true. Give the crypt a drone or drip ambience bed and start the rival's music when he engages.

### 10. MINOR: Sol reads as a black silhouette at night and in backlit views, so the relaxed arm and walk can barely be seen
- **Evidence:** `qa_r3/sheet_sol.jpg`, `qa_r3/web_b/b03_settled.png`, `qa_r3/web_f/f02`–`f07`. The crypt floor centre is very dark too.
- **Fix:** the critic's V8. Add a moon or key rim on Sol, and a soft fill light in the crypt over the duel floor.

## Polish

### 11. POLISH: `?undercroft` alone stays on the main menu
It only takes effect inside a Hunt, so you need `?autohunt&undercroft`. Either make `undercroft` imply `autohunt` in `main_menu.gd:_autohunt_wanted()`, or document the pair.

### 12. POLISH: "Subtitles" appears on two tabs
It is in both Preferences and Accessibility (`web_a/a04`, `a06`). Keep it in Accessibility only.

### 13. POLISH: the key-hint strip never mentions the Weapon Art (V)
`hud.gd KEYS_HELP` lists X crouch and Alt / Z walk at `f452aff`, but not V. The Art icon (bottom right) does show "V".

### 14. POLISH: Esc-resume from pause logs `PAGEERROR: A user gesture is required to request Pointer Lock`
- **Evidence:** `web_f/console.txt`.
- **Fix:** don't request pointer lock on a keyboard resume; wait for the next click.

### 15. POLISH: the benchmark reports the wrong renderer
`bench.gd:374` reports `"renderer": "forward_plus"` (the project setting) while running Compatibility. Report `RenderingServer.get_current_rendering_method()` instead.

### 16. POLISH: engine errors in the logs
- `ERROR: Lambda capture at index 0 was freed` shows 8 times in the smoke run and once in the bench camp fight. A tween or timer lambda outlives its node.
- Headless runs log 6,734 `Parameter "m" is null`.

---

## Re-check of round 2

| R2 # | Issue | R3 status | Evidence |
|---|---|---|---|
| 1 | Parry script error in boss fights; adds not parried | **Fixed** | Smoke: "parry turns the boss swipe aside", "an add is parried during a boss fight". No SCRIPT ERROR in `smoke.log`. |
| 2 | `assets_staging` in the `.pck` | **Fixed** (but the pck grew to 50.1 MB, #4) | `export_presets.cfg` exclude filter, plus a smoke check |
| 3 | Esc / Tab during the intro | **Fixed** | Smoke: "intro: Tab opens no Coat, Esc skips it without pausing" |
| 4 | 300–1,000 draws, about 1M primitives | **Largely fixed** | 107–295 draws and 108–335k primitives on Very Low to Medium (#8 table) |
| 5 | Navmesh in tanks, no kill plane | **Fixed** | Smoke: "a fall out of the world puts Sol back", "safe_ground never answers inside a solid" |
| 6 | Hub list clipped | **Fixed** | `web_a/a08_hub.png` (it scrolls). Smoke: "hub lists all 10 contacts and fits". |
| 7 | Lunge and leap rarely fire | **Fixed** (native) | Smoke: "a vampire beside an idle Sol hops back and lunges" |
| 8 | Camera occluded or inside enemies | **Mostly fixed** | Smoke: awning blockers, enemy hidden. Foreground signposts still cover part of the frame at the trail deploy (`web_b/b03`). |
| 9 | Knight silent | **Fixed** | Smoke: "every boss has a voiced intro and death line" |
| 10 | Charged slash double hit | **Fixed** | Smoke: "one heavy hit" |
| 11 | Options taller than 720p; V-Sync on the web | **Fixed** | `web_a/a02`–`a06` |
| 12 | Night card over the stick and map | **Fixed** for overlap; size remains (#5) | `web_b/b12_map.png`, `web_c/c07` |
| 13 | Touch buttons over the intro | **Fixed** (code: `touch_controls._in_play` excludes "intro") | Not re-shot: the autohunt runs skip the intro |
| 14 | Phone hub clipped | Not re-tested on a phone | — |
| 15 | Two deploy points face an obstacle | Not re-tested | — |
| 16 | "Old Gristle Of The Pines" | **Fixed** (`poi.gd:47`) | Code |
| 17 | Vampire barks during the Abomination | **Fixed** (code, `audio.gd` boss guard) | Not heard |
| 18 | Navmesh console errors | **Fixed** on the web | `web_b`, `web_c` and `web_f` consoles: 0 navigation lines. The headless "m is null" noise remains (#16). |
| 19 | Lake invisible wall | **Fixed** | Smoke: "wadeable right across (1.30 m deep), no invisible wall". `nat_views/medium_lake.png`. |
| 20 | Hint strip stays all Hunt | Can't verify at 1 fps | The fade is on a 30 s game timer; only seconds of game time passed |
| 21 | Test gaps | Partly closed | Audio is now measured. Gamepad, Hunt Again and the real-GPU feel are still untested. |

## Owner's open complaints (for the critic)
- **The walk was the run slowed:** addressed at `f452aff` with a bought `Casual_Walk_inplace` clip on a 1.1 m/s blend point. The walk speed is measured at 1.10 m/s, but its look at real frame rate was not judged here.
- **The right arm stays raised when sheathed:** addressed. Smoke checks the hand hanging; the native idle shows both arms down (`nat_sol/sol_idle_front.png`, dark). In the web at `b052634`, the sword was still in hand long after the heavy (`web_b/b11`), but only a few game seconds had passed at 1 fps.
- **No crouch:** now present. X / D-pad Down / the CROUCH touch button, a toggle, the "enemies notice you later" prompt, and a lower capsule. The crouch clips are still pending.
- **Hip-hop boss music:** pending credits. Marcus and the Abomination have their own themes (smoke); the others keep the generic boss track.

## Works well
- **Web audio is fixed:** silent until a gesture, then audible on menu, Hunt and phone, with no bus cycle. CI guards it.
- **The settings panel is solid:** 5 tabs, fits 720p and the phone, works from the menu and from pause. The presets apply (Very Low shows 55% scale, no shadows, 55 m view). Auto-detect gives Medium on desktop web and Low on the phone.
- **Frame budget:** gameplay views are inside a phone budget on Very Low to Medium, down 2–4× from R2.
- **The Undercroft Depths:** a real candle-lit crypt under the plaza, a named rival with a name plate, and the walk down and back up, all checked.
- **Nia's Rack:** 9 weapon types with Arts listed and prices; the list scrolls.
- **Weapon Arts and special combos:** every type's chain, heavy and Art lands (smoke). The ART touch button and V work in the browser.
- **The Blood Rite:** 3 distinct offers, one suited to the blade, a paused world, and keyboard, pad and click input.
- **Night modifiers:** shown on the card and the phase line, and they vary by seed.
- **The graveyard:** shed, open grave, Old Amos's line, and crows that take off.
- **Crouch and walk:** both work by keyboard and touch, with clear prompts.
- **The console is clean** on the web (R2's navmesh noise is gone).
- **R2 fixes hold:** parry in boss fights, the kill plane, the lake wade-through, the Options fit and the hub scroll.

## Top 10 to fix next
1. **#1** The Coat can't be closed on a phone. Fit the panel to the viewport and add a ✕ (a soft-lock blocker).
2. **#2** Sol T-poses through the whole Descent: keep his animation ticking while `deploy.gd` disables physics.
3. **#3** The mirrored, floating "HOLLOW PINES" sign over the Descent title.
4. **#4** The `.pck` is 50.1 MB plus a 35 MB wasm: audit the new audio and models, and lazy-load boss assets per night.
5. **#8** The Map screen is the most expensive frame (341–542 draws): batch the icons and stop the 3D world behind it.
6. **#7** Blood Rite card text overflows (a lost "%" and a clipped tag).
7. **#5** Shrink the night card or auto-collapse it after about 4 s (desktop top centre, phone bottom centre over Sol).
8. **#6** Phone: hide the action buttons while the map is open (they cover the legend).
9. **#9** Give the crypt an ambience bed and start the rival's music when he engages.
10. **#10** Make Sol readable at night (a rim light, and fill in the crypt) so the new arm, walk and crouch poses can be seen.
