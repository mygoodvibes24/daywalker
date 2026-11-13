# DAYWALKER: Blood and Moon — Critic Report

Reviewed: commit `faa2cbc` (Godot 4.3 prototype + STORY_BIBLE v0.1), 2026-11-13.
Method: read every script line by line, ran the headless smoke test, wrote two throwaway probe scripts (curbs, pathing, slow-motion, spawns, node counts), exported the web build and played it in headless Chromium at 1280x720 and phone size (390x844). Details are in the Evidence section at the end.

> **Fix status (update, 2026-11-13):** bugs 1–8, 10, 11, 13, 14 and 16–22 are fixed, and each critical or high bug has a regression check in `game/tests/smoke_test.gd`. Attack tokens (at most 2 enemies strike at once, the rest circle) and a gentler, out-of-combat-only sun heal (1 HP/s) from section 4 are also in. Still open: 9 (frenzy has no downside, which is a design decision), 12 (phone layout: the title screen now says "best on desktop" on touch devices), 15 (only a white "recovered" flash so far), and everything in sections 4–8 beyond that. Bug 21: CI now caches Godot, fails on import errors and runs the smoke test, but it still deploys from this feature branch on purpose so the playable build stays current.

---

## 1. Verdict

| Area | Score | One-line reason |
|---|---|---|
| Game Feel | **4 / 10** | The speed numbers and dash are good, but a 25 cm curb stops him dead, enemies get stuck on walls, and there is no sound at all. |
| Visuals | **3 / 10** | Honest "programmer art" made from boxes. The night city has real mood; the hero reads as a black blob from behind. |
| Story | **7 / 10** | Strong hook, great villain dynamic, a meaningful bite and Hunger mechanic. Too close to *Blade* and *Underworld* in places, and the women orbit the hero. |
| Code | **5 / 10** | Clean, short and readable for a prototype, but it is all built in code with no scenes, no typing between scripts and no state machine. It won't survive a story game as is. |
| Web Readiness | **6 / 10** | Exports cleanly, single-threaded (works on any host), no console errors. 35 MB wasm, no touch controls, HUD is unreadable on phones. |
| **Overall** | **4 / 10** | A working, honest first prototype of the combat loop, but a long way from the vision. |

**Summary.** The prototype proves the core idea, *fight, stagger, bite to heal, manage Hunger, survive day and night*, and the tuning numbers show someone thought about speed. But two verified bugs break the basics: the player and the enemies can't step onto the sidewalks, and enemies chase in a straight line, so most of them never reach you. Fix movement and AI, add audio and real animated characters, then build the Prologue as a vertical slice before you add anything else.

---

## 2. What works

*In plain English: the bones of a good action game are here.*

- **The core loop is right.** Hit an enemy down to 25%, a red orb appears, press E to bite and heal. Three blood types with different effects (human = big heal + Hunger, vampire = speed, wolf = rage that burns). That is the story bible's best idea, and it is playable.
- **The speed numbers are genuinely fast.** Walk 7.5 m/s, sprint 13 m/s (faster than an Olympic sprinter), dash 34 m/s with 3 charges, double jump, FOV kick on dash and sprint, coat flare, after-image ghosts.
- **Hit-stop and screen shake** on every blade hit (`player.gd:289-291`). This is the single most important game-feel trick, and it's already in.
- **Enemy attacks are telegraphed:** a 0.38–0.45 s wind-up where the enemy leans back and its eyes flare (`enemy.gd:168`, `enemy.gd:186`, `enemy.gd:197`).
- **The day/night cycle has teeth:** vampires burn at sunrise, werewolves transform at nightfall with an elastic "grow" tween and camera shake, and the blood bank restocks at dawn.
- **The night city looks moody** for primitives: lit window bands, rooftop neon, warm lamp pools, a red glow at the Undercroft (see `night_1.png`).
- **There's a smoke test,** and it passes. Most prototypes have none.
- **The web export uses the single-threaded template,** so GitHub Pages works without special headers.

---

## 3. Bugs found

*In plain English: two bugs break the game's basics. Sol can't step up a curb, and enemies can't find their way to you. Fix those first. The rest are smaller.*

"Verified" means I reproduced it by running code. "Read" means I confirmed it by reading the logic carefully but didn't run it. "Unsure" means plausible but not confirmed.

| # | Severity | Where | Problem | Suggested fix | How confirmed |
|---|---|---|---|---|---|
| 1 | **Critical** | `main.gd:136` (sidewalk `static_box` 0.25 m tall) | **Sol can't walk or sprint onto any sidewalk.** He stops dead at the curb (probe: player stuck at z=23.16 against a curb at z=23.5, both walking and sprinting). The capsule meets the 25 cm edge at about 70°, which Godot treats as a wall. The only way up is to jump. Every block in the city is surrounded by this curb. | Easiest: remove collision from the sidewalk slabs and keep them as visuals (sink them or accept the 25 cm visual offset). Better: add step-up logic (test-move up 0.3 m, forward, then down) in the player and enemy movement. Or replace the slab edge with a small ramp collider. | Verified (probe) |
| 2 | **Critical** | `enemy.gd:155-166` | **Enemies chase in a straight line with no pathfinding.** If a building or curb is between you and them, they push into it forever. Probe: 12 enemies spawned around a player standing on a street, and after 15 s of game time only **2 of 12** reached him. The rest were pinned on curbs or walls (`is_on_wall()=true`, stuck at x=23.1 against the curb at x=23.5). It makes the game far easier than intended and looks broken. | Bake a `NavigationRegion3D` navmesh at startup (the city is generated, so bake after `_build_city()`), give each enemy a `NavigationAgent3D` with avoidance turned on, and steer along `get_next_path_position()`. Fix bug 1 at the same time, or the navmesh will route around every curb. | Verified (probe) |
| 3 | **High** | `main.gd:336-338` (`set_slowmo`) | **Slow-motion effects stack badly.** After a perfect dodge (0.3x for 0.8 s), landing a blade hit within that window sets time to 0.06x **for the rest of the 0.8 s**, because `minf()` keeps the lowest scale and `timescale_until` keeps the longest end time. Probe: 400 ms after "dodge then hit", `Engine.time_scale` was still 0.06 when the hit-stop should have ended after 50 ms. Dodge-then-counter is exactly what players will do, so the game will freeze almost solid for about half a second at the best moment. | Track each effect separately (store a list of `{scale, end_time}` and use the minimum scale among the effects that haven't ended yet), or make hit-stop a short separate freeze that ends and then restores the active bullet-time scale. | Verified (probe) |
| 4 | **High** | `enemy.gd:161-164` | **Enemy attacks can't be sidestepped.** When the wind-up ends, the player takes damage if they're within `attack_range + 0.7`, with no check that they're in front of the enemy. Strafing around a wolf doesn't help. A related issue: a **perfect dodge only triggers if the dash keeps you in range** when the wind-up ends. A normal dash (5.4 m) carries you out of range, so the hit just misses with no reward. | Add a facing check (`fwd.dot(to_player) > 0.5`) and lock the attack direction at the start of the wind-up. Trigger the perfect dodge whenever the player dashed in the last ~0.2 s before an attack that would have hit, not only while the dash is active. | Read |
| 5 | **Medium** | `main.gd:217-218` | **The very first night is a full moon** (`night_count % 3 == 1` and night 1 is the first night). Probe: `night_count=1, full_moon=true`. New players get the hardest night first (70% wolves at 160 HP, spawning every 1.6 s). The README says "every 3rd night" and the bible says every 7th. | Use `night_count % 3 == 0 and night_count > 0` (nights 3, 6, 9…), or follow the bible (every 7th). | Verified (probe) |
| 6 | **Medium** | `main.gd:226-246`, `hud.gd:205` | **The game runs behind the "CLICK TO HUNT" title screen.** Time passes, enemies spawn and can attack you before you've started (screenshot `day_0_title.png`: the clock had moved from 13:12 to 13:25 before the first click). | Keep the world paused (`get_tree().paused = true`, with the HUD set to `PROCESS_MODE_ALWAYS`) until the player clicks. | Verified (screenshot + read) |
| 7 | **Medium** | `enemy.gd:137-138` | **Werewolves never change back.** They transform at nightfall, but nothing reverts them at sunrise, so 110–160 HP wolves keep roaming in daylight. The bible says they look human by day. | At sunrise, play a reverse tween and restore their civilian stats, or have them flee or despawn. | Read |
| 8 | **Medium** | `enemy.gd:205-207` + `player.gd:280-288` | **The combo kills the enemy you wanted to bite.** Any hit on a staggered enemy kills it outright, and the combo hits everything in its arc. In a group fight you constantly finish off the staggered enemy (no heal) while aiming at another. Soft-lock (`player.gd:271`) also prefers the nearest enemy even if it's staggered. | Make staggered enemies ignore incidental damage from swings aimed at someone else (or need a dedicated "execute" input), and make soft-lock skip staggered enemies. | Read |
| 9 | **Medium** | `player.gd:226-231`, `player.gd:339-340`, `player.gd:248` | **Frenzy is a pure power-up, not a danger.** It gives 2x damage, 1.25x speed, half damage taken and +3 HP/s. The bible says you "lose control and might bite someone you love". Right now players will *want* max Hunger. | Take some control away (auto-target the nearest living thing, inputs randomly ignored, forced bites), and make biting a human during frenzy cost something lasting. | Read |
| 10 | **Medium** | `player.gd:399-419` | **Ghost trails are expensive.** Every 0.025 s during a dash the code duplicates the whole 28-mesh body with a new transparent material: about 6–7 ghosts × 28 = ~190 transparent meshes. Frenzy spawns them for 8 s straight. Transparent objects are the most expensive thing for web GPUs. | Use one merged low-poly silhouette mesh, a small pool of 4–6 reused ghosts, and one shared material per colour. | Read |
| 11 | **Low** | `hud.gd:211` | The HUD says **"DAYWALKER (sunlight heals you)" at night** (see `night_2_fight.png`). That's misleading. | Show "(sunlight heals you)" only when `main.daylight() > 0.3`. | Verified (screenshot) |
| 12 | **Low** | `project.godot` stretch + fixed font sizes in `hud.gd` | **On a phone in portrait the HUD is unreadable** (text about 5 px; see `mobile_1.png`), because the 1280-wide layout gets shrunk to fit 390 px. | Use `stretch/aspect="keep_height"` or a responsive layout, and set a minimum UI scale on small screens. Or declare the game desktop-only and say so on the title screen. | Verified (screenshot) |
| 13 | **Low** | `main.gd:67` + `player.gd:115-116` | The click that captures the mouse **also fires an attack** (LMB is bound to "attack"). On web, pressing ESC releases pointer lock, and the click to re-capture swings the blade again. | Consume the capture click (`get_viewport().set_input_as_handled()`), or ignore attack input for one frame after capture. | Read |
| 14 | **Low** | `main.gd:287` | The spawn cap counts enemies that are already dead but still playing their death tween (about 2 s for wolves), so the effective cap is lower than intended. | Count only living enemies, or reparent dead ones out of `enemies_root`. | Read |
| 15 | **Low** | `enemy.gd:154` | When stagger runs out, the enemy's HP is set to 45% of max, so a wolf at 1 HP heals to 72 HP. That's probably intended, but it isn't communicated. | Keep it, but show a "recovered" flash so players learn the window matters. | Read |
| 16 | **Low** | `enemy.gd:101-106` | An enemy hit during the day and still staggered when night falls transforms back to **full** HP but stays staggered (one hit kills it). This is an odd edge case. | Clear stagger on transform. | Read |
| 17 | **Low** | `main.gd:304-314` | If 16 random tries fail, the fallback spawn point can be closer than 18 m. Probe: 9 out of 2000 spawns. It's rare, but an enemy can pop in on screen. Spawns never overlapped buildings (0/2000). | After the loop, return the best candidate that is still >18 m away, or skip this spawn. | Verified (probe) |
| 18 | **Low** | `hud.gd:224`, `hud.gd:227`, `main.gd:343` | The max dash count and blood bank size are hard-coded as `3` in three places instead of using `MAX_DASH` and `LAIR_MAX`. | Use the constants. | Read |
| 19 | **Low** | `export_presets.cfg` | `tests/smoke_test.gd` ships inside the web `.pck` (seen in the export log). | Set `exclude_filter="tests/*"`. | Verified (export log) |
| 20 | **Low** | `main.gd:39` | `"night" in url_query` matches any query containing "night" (for example `?knight=1`). | Parse the query string properly. | Read |
| 21 | **Low (unsure)** | `.github/workflows/web.yml` | `--headless --import . \|\| true` hides any import failure, and the smoke test is never run in CI. Every run downloads the full ~1 GB export-template bundle with no cache. | Remove `\|\| true`, add a smoke-test step that fails the build, and cache the templates (`actions/cache`) or use a prebuilt Godot CI container. | Read |
| 22 | **Low** | `main.gd:186-188` | The lair's stone ring has no collision, so you walk through it (only the four pillars are solid). | Add a ring collider or step it into the ground. | Read |

Things I checked and found **OK**: input actions survive the restart reload (`_bind` checks `has_action`), `Engine.time_scale` is reset on death and restart, HUD timers correctly use real time when time is slowed (`hud.gd:203`), the camera spring arm doesn't collide with the player, and spawns never land inside buildings.

---

## 4. Game feel: issues and fixes

*In plain English: on paper he's fast and the combat has the right ingredients, but it doesn't feel fast or satisfying yet. That's mostly because there's no sound, no animation, and the world fights the movement.*

**Speed**
- The numbers are fast (sprint 13 m/s, dash 34 m/s). But **the city geometry kills the speed fantasy**: 7 m wide streets, curbs that stop you (bug 1), and no vaulting or wall-running. Speed needs space and flow, so give him long avenues, rooftops connected by gaps he can jump, and an automatic vault over low obstacles.
- **Movement starts and stops instantly** (velocity is set directly, `player.gd:176-177`). That's snappy, but it feels weightless. Add a very short acceleration ramp (~0.08 s) and a skid or slide when he changes direction while sprinting. It sells speed better than raw top speed does.
- **There are almost no speed cues.** Add a radial blur or speed lines at sprint and dash, wind audio, dust or rain kicked up, and a dash "whoosh". These matter as much as the numbers.
- **Bullet-time slows Sol too** (`Engine.time_scale` slows everything). In the fantasy only the world slows. Scale the player's own delta back up during perfect-dodge slow-motion (or give him a 2–3x speed multiplier while it lasts) so he gets a few "free" moments.

**Combat**
- **No audio at all.** This is the biggest feel problem in the whole project. Blade swishes, flesh hits, a wet bite with a heartbeat, a wolf transformation crack and growl, rain, distant jazz. Even free CC0 sounds would double the perceived quality overnight.
- **No animation.** Characters are rigid capsules that bob. Only the sword arm swings. Enemies have no hit reactions beyond a white flash and a push, and the bite is just a lean. The bite is the signature move, so it needs a grab, a lunge to the neck, a camera push-in and a blood spray.
- **No blood VFX in a vampire game.** Add a particle burst on hit and on bite, and decals on the street.
- **Enemies don't surround or take turns.** They all run straight at you, block each other, and when they arrive they all attack at once (no attack-token system). Add (a) navmesh + avoidance (bug 2), (b) "slots" around the player so they ring you, and (c) a token that lets only 1–2 enemies attack at a time while the rest circle. This is how Batman Arkham-style combat stays readable.
- **One attack type per enemy.** Give vampires a quick lunge and a slow grab (that you have to dash), and wolves a leap and a sweep. Use colour or shape to show which attacks can be dodged and which can be countered.
- **No counter or parry,** though the bible promises "counters, finishers". A simple counter window (press attack when the eye-flare peaks) would give the telegraph a purpose.
- **Readability:** from the default camera Sol is a black silhouette (`day_1_start.png`) with no visible locs, glasses or face. Add a rim light on the hero and a slightly higher camera, and give the coat a subtle sheen.

**Difficulty curve**
- Night 1 is a full moon (bug 5), which is the hardest night first.
- **Daytime is trivially safe:** at low Hunger the sun heals 2.5 HP/s (`player.gd:235-236`), which out-heals 4 civilians hitting for 7. Lower it to ~1 HP/s or make it work only out of combat.
- Up to 14 enemies at once, all attacking simultaneously, will feel unfair once pathfinding works. Pair the attack tokens with the higher spawn cap.
- Wolves on a full moon take ~120 damage to stagger (about 9 hits). That's fine for a "big" enemy, but they need a clear weak point or stun move or they become damage sponges.

**Feedback**
- There's no damage direction indicator, no enemy health readout (you can't tell how close to stagger an enemy is), and no hit counter or combo text. A thin health bar over each enemy that turns red at 25% would teach the stagger rule without words.

---

## 5. Gap vs the vision and a realistic roadmap

*In plain English: the story bible describes a large, cinematic, multi-year game. This is a combat sandbox with box people and no story yet. That's normal at this stage, but the next steps should go toward one polished slice, not more features.*

### What exists vs the bible

| Bible feature | Status |
|---|---|
| Blood Dash x3, bullet-time on perfect dodge, Sun Sprint (faster dash regen by day) | Present (basic) |
| Bite with 3 blood types, Hunger meter, Frenzy | Present (Frenzy has no downside) |
| Day/night cycle, vampires burn, wolves transform, full moon | Present (full moon cadence differs) |
| Undercroft | Entrance + blood bank only, no interior |
| Wall run / vault / slide-strike / grapple blade | Missing |
| Weapons and tools (UV grenades, wolfsbane, silver), counters, finishers, blood/day powers | Missing |
| Enemy variety (Thralls, Courtiers, Gargoyles, Mimics, Skinwalkers, bosses) | 2 generic types |
| Named characters: Lucien, Seraphine, Nia, Rook, Wren, Reyes, Odette | None in game |
| Story missions, dialogue, choices, Bloodline journal, permadeath of characters | None |
| Districts (Velvet Mile, Old Quarter, Hollow Pines, Docks, Bayou, Midtown) | One generic grid |
| Human civilians / innocents (core to Hunger morality) | Missing: every "civilian" is a hostile wolf |
| Photoreal faces, performance capture, body-horror transformations | Not attempted |
| Audio, music, VO | None |

### The "ultra-realistic like Until Dawn" goal: an honest assessment

- **The bible and the prototype contradict each other.** Section 12 says Unreal Engine 5 + MetaHuman; the prototype is Godot 4.3 Compatibility with code-built boxes. You need to **decide now**, because everything downstream (assets, tools, hiring) depends on it.
- ***Until Dawn* fidelity comes from a ~100-person studio, Hollywood actors in full face and body capture, and years of lighting work.** No solo or small indie team matches that in any engine. What *is* achievable: a "prestige-horror look" with strong lighting, fog, rain, wet reflections, film grain, cinematic cameras, decent mocap, and good (not photoreal) faces. Treat Until Dawn as the target *mood and structure*, not the target polygon count.
- **If you stay in Godot (reasonable for a small team):**
  - **Desktop is the real game:** the **Forward+** renderer (volumetric fog, SDFGI or baked lightmaps, SSR for wet streets, SSAO, glow, TAA/FSR2), imported glTF assets, and `AnimationTree` state machines.
  - **The web build is a demo**, kept on **Compatibility** with simpler lighting. Ship both from the same project with quality presets. Don't let the web limits dictate the main game's look.
  - **Characters:** Reallusion Character Creator 4 (or Daz, or a hired artist) → rigged glTF. For placeholders use Mixamo animations retargeted with Godot's `SkeletonProfileHumanoid`. Epic's current MetaHuman licence reportedly allows use outside Unreal; check the licence terms before relying on it.
  - **Mocap:** Rokoko or Move.ai (camera-based, cheap) for body. iPhone ARKit face capture → 52 blendshapes, imported as shape-key animation for faces.
  - **Transformations:** blendshape morphs plus a mesh swap, hidden by camera cuts, fur cards and particles. Alembic body-horror simulations are not realistic in Godot today.
- **If photoreal faces really are the non-negotiable heart of the game,** UE5 + MetaHuman is the shorter road, as the bible itself says. That means throwing away this GDScript code (cheap, it's ~1,300 lines). Prototype the combat feel in Godot now if you like, but **pick one engine before you build the vertical slice.**

### Top 10 next steps (in priority order)

1. **Fix movement and AI basics:** curb collision or step-up (bug 1), navmesh pathfinding + avoidance (bug 2), the slow-motion stacking bug (3), and a facing check on enemy attacks (4).
2. **Audio pass:** swings, hits, bite, footsteps, rain ambience, a heartbeat that rises with Hunger, and music stingers at nightfall and full moon. It's the cheapest, biggest quality jump.
3. **Decide the engine and fidelity target** (Godot Forward+ desktop with a Compatibility web demo, or UE5) and write it into the bible.
4. **A real Sol:** one rigged, animated character (idle, run, sprint, dash, 3-hit combo, bite, hit react, death) through an `AnimationTree`. Then one vampire and one wolf the same way.
5. **Combat framework:** player and enemy state machines, attack tokens and surround slots, counters, blood VFX, enemy health bars, and a frenzy that takes control away.
6. **Restructure the code for a story game** (section 7): scenes for player, enemies and HUD; a `GameState` autoload; signals; enemy stats as `Resource` files.
7. **Build the Prologue as the vertical slice** (the bible's own plan): the nightclub blood-den interior, the tutorial beats, the first bite, freeing Rook (first choice), and an escape run. Make one great 15-minute level, not a bigger city.
8. **A dialogue and choice system plus saves:** e.g. Dialogue Manager or Yarn Spinner for Godot. Store choices as flags in `GameState` and save them, which becomes the Bloodline journal.
9. **The Undercroft interior** as a walkable hub scene (blood bank, Nia's lab, crypt wall that fills with your kill count), loaded from the plaza entrance.
10. **Platform polish and CI:** a title screen that pauses, a pause/settings menu (mouse sensitivity, invert-Y, volume), gamepad bindings, touch controls or an explicit "desktop only" message, the smoke test in CI, and template caching.

---

## 6. Web readiness

*In plain English: it loads and runs in a browser without errors, but it's a big download, it would struggle on weak laptops, and it doesn't work on phones.*

**What's good**
- `variant/thread_support=false` → no `SharedArrayBuffer` / COOP-COEP headers needed, so it works on GitHub Pages and itch.io.
- No console errors in Chromium. It booted in about 15 s on a GPU-less machine.
- `canvas_resize_policy=2` (adaptive) and `focus_canvas_on_start=true` are correct.

**Load size**
- `index.wasm` is **35.4 MB** (about **8.0 MB gzipped**, measured). `index.pck` is only 44 KB because everything is built in code. Check in browser DevTools that your host serves the wasm compressed. If it isn't compressed, first load is slow on mobile data.
- To shrink it: build a custom web export template with unused modules disabled (2D physics, advanced text server, unused importers, etc.). Size-optimised custom templates often land at about half the size. Do this later, once the module needs are known.
- There's no custom loading screen (the default Godot one). Add a branded `html/custom_html_shell` with a progress bar and the title art.

**Rendering cost** (judged from the code and node counts, not from the test machine's FPS)
- At startup the scene has **905 nodes, 546 MeshInstance3D, 532 unique mesh resources, 53 materials, 8 lights, 158 static bodies** (probe). Each building box and window band is its own mesh, so there's essentially **no batching**: hundreds of draw calls before shadows.
- The **directional sun shadow** is always on (`main.gd:99`), with 60 m distance, and every building casts shadows. That's roughly another full draw pass for casters, per shadow split.
- **6 street-lamp OmniLights + 1 lair light** near the plaza. In the Compatibility renderer each light touching an object adds an extra render pass for that object, so the plaza at night costs several times as much. The lamps are correctly hidden in daylight.
- Each enemy is 12 meshes with unique materials (needed for its colour tweens). With 14 enemies plus the player's ghost trails (bug 10), a fight can add ~300–500 transient draw calls.
- MSAA 2x is on (`msaa_3d=1`), which is moderate on integrated GPUs.
- **Fixes:** merge each city block (buildings + windows + neon) into one `ArrayMesh` at build time, or use `MultiMeshInstance3D` for windows. Turn off `cast_shadow` on window bands and neon. Fake the lamp pools with emissive decals or unshaded light cones instead of real OmniLights on web. Add a quality setting that disables shadows and MSAA. Pool the ghost meshes.

**Mobile and touch**
- No touch controls, no gamepad bindings, and the HUD is unreadable at phone size (bug 12). Mouse look depends on pointer lock, which mobile browsers don't support.
- Recommendation: officially support **desktop browsers with keyboard/mouse and gamepad** for now. Show a "best on desktop" notice on touch devices. Add virtual sticks only if mobile becomes a goal.

**CI/CD** (`.github/workflows/web.yml`)
- It works, but it downloads ~1 GB of templates every run with no cache, hides import errors with `|| true`, doesn't run the smoke test, and also deploys from a feature branch (`claude/day-walker-game-concept-mz8vvv`), so a test push can overwrite the live site. Restrict deploys to `main`.

---

## 7. Code quality and architecture

*In plain English: the code is tidy and easy to read for a prototype, but it's built in a way that will get painful as soon as you add story, characters and levels.*

**Good**
- Small, focused files (~1,300 lines total), clear names, useful comments, and helpers in `util.gd`.
- Typed local variables in most places, constants for the key tuning values in `player.gd`.

**Problems that will hurt at scale**
- **Everything is built in code.** `main.tscn` is an empty node; the city, player, enemies and HUD are all assembled in scripts. Nobody can open a level in the Godot editor, move a lamp, or drop in a 3D model without editing code. A story game needs hand-built scenes: the nightclub, the Undercroft, cutscene sets.
- **Untyped cross-references.** `var main` in player, enemy and HUD is untyped, and so are `player`, `target` and `bite_target`. Typos become runtime crashes instead of editor errors. Add `class_name Player`, `class_name Enemy`, etc. and type the variables.
- **Tight coupling.** The player calls `main.hud.popup()`, enemies call `main.on_enemy_killed()`, and the HUD reads player fields directly every frame. Use **signals** (`player.bitten.emit(blood_type)`, `enemy.died.emit()`) and a `GameState` autoload so systems don't need to know about each other.
- **Timers instead of states.** The player is driven by ~15 float timers (`dash_t`, `swing_t`, `lunge_t`, `bite_t`, `frenzy_t`…) checked in long `if` chains. Every new move (wall-run, grapple, counter, slide) multiplies the edge cases. Use a simple state machine (a node per state, or an enum with enter/exit) plus `AnimationTree` states.
- **Magic numbers everywhere.** Enemy stats are literals inside build functions (`enemy.gd:80-82`, `96-98`, `105-108`), blood heals are inline (`player.gd:303-316`), and drain returns `0/1/2` instead of an enum. Move them into `Resource` files (e.g. `EnemyStats.tres`, `BloodType.tres`) so a designer can tune without code.
- **No save system, no scene manager, no dialogue or data layer.** These are the backbone of an Until Dawn-style choice game and should be designed early.
- **Testing:** the smoke test is a good start. It doesn't cover movement, AI reaching the player, the slow-motion timing or restart. The probes in this review found bugs 1–3 in a few minutes, so tests like them are worth keeping.

---

## 8. Story critique (STORY_BIBLE.md)

*In plain English: the story has a strong hook and a memorable villain, but several pieces sit very close to* Blade *and* Underworld *and should be changed. The women characters need goals of their own, not just roles around Sol.*

**Strengths**
- **A clear, marketable hook** in one sentence: *framed by both sides, the only one who walks in the sun*.
- **The bite and Hunger system is story told through mechanics.** Healing costs you your humanity, and the game remembers whom you fed on. That's the best idea in the document.
- **Lucien** is a great antagonist type: funny, vain, fatherly and dangerous. The "my father's son" secret ending is the most emotional beat in the bible.
- **Werewolves as working-class families** against vampire old money is a fresh class angle on a tired rivalry.
- **The Crypt Wall** and **ending 3 ("peace through genocide, and he isn't sure he was right")** show real moral ambition.
- **The day/night and full-moon structure** gives the open world a natural rhythm.

**Too close to existing IP. Change these before anything goes public.**
- ***Blade* (Marvel):** a half-vampire who walks in daylight; born as his mother was bitten while pregnant; she dies giving birth; trenchcoat, dark glasses, silver blades; "**Daywalker**" is Blade's signature nickname; **Nia Okafor, a hematologist** who patches him up and makes serums, mirrors Karen Jenson from *Blade* (1998); and the vampire who bit his mother turns out to be the villain. Individually these are genre tropes, but together they read as a *Blade* reskin. Suggestions: drop "Daywalker" as the title (keep it as a nickname at most), change the origin (for example he was turned as a child and the turning was interrupted, or he's the result of Nia's mentor's experiment), make Nia something other than a hematologist (a coroner, or a blood-bank logistics fixer), and give Sol a signature look beyond the trenchcoat and shades (the locs are a good start).
- ***Underworld*:** vampires against werewolves with a secret history; a **vampire–werewolf hybrid** bloodline as the big twist; and the names **"Lucien"** (*Underworld*'s werewolf leader is *Lucian*) and **"Marcus"** (an *Underworld* elder). Rename both, and rethink "hybrid army" as the climax twist. Perhaps Seraphine is making *sun-proof* vampires from Sol's blood rather than wolf hybrids.
- **Batman language** ("Batcave", "Alfred plus Oracle") is fine as internal shorthand. Keep it out of public material.

**Clichés to watch**
- A prophecy ("a child of sun and blood…") delivered by a riddling bayou root-woman. Mama Odette risks the "magical Black woman" trope, and Vodou/hoodoo used as spooky set dressing. Give Odette her own stake in the conflict (she owes Lucien, or she failed to save Grace), and get cultural input on how hoodoo is portrayed.
- The presumed-dead ex-queen as the hidden villain, and twins who "share one mind".
- The post-credits "two babies born that night" sequel hook is fun but very familiar.

**The women's depth**
- Nearly every woman is defined by her relationship to Sol: Nia is helper, romance and possible death; Rook is enemy, then rival, then romance; Seraphine is a seductress; Reyes doesn't believe until she does. The Raid choice "**save Nia or save Rook**" makes both women prizes in the hero's dilemma, and Nia's possible Act 2 death edges into "fridging" (killing a woman to fuel the hero's story).
- **Fixes:** give each woman a goal that would exist without Sol and that can clash with his.
  - **Nia:** she secretly needs Sol's blood for her own research or a dying relative, so trust becomes a real choice.
  - **Rook:** she wants to break the bloodline curse for the whole Pack, even if that means using Sol.
  - **Reyes:** she has a solved-case record to protect, and the truth would ruin her.
  - **Seraphine:** give her a sympathetic *why*, for example escaping Lucien's centuries of control, so she is persuasive rather than merely seductive.
  - Let the Raid choice be *their* choice too: they can refuse to be rescued, or rescue Sol.
  - **Mother Wren** is already the best-written woman, because she has her own grievance and power.
- **The Until Dawn lesson:** that game's tension comes from an *ensemble* of playable characters, any of whom can die. The bible has only one playable character, so "anyone can die" happens only around Sol. Consider short playable chapters as **Rook, Reyes or Nia**. It deepens them and fits the format better.

**Pacing**
- **Act II is overloaded:** the prophecy, the father reveal, a team-up and romance, the lair raid, the villain twist and a boss confrontation all happen in one act. Move the father reveal to the end of Act I (it reframes Lucien's charm in hindsight), and spread the raid and twist further apart.
- **Act I needs its own mid-point mystery beat** (a lead the player investigates) so the frame-job plot is active, not just exposition.
- **Five endings plus seven major choices** is a lot to write and test for an indie team. Plan for 3 endings for the first release, and make the choices change scenes and who survives (Until Dawn style) rather than whole branches.
- Make the full-moon cadence consistent with the game (the bible says every 7 days; the prototype uses every 3 nights).

---

## 9. Evidence

**Tests run**
- `godot --headless -s res://tests/smoke_test.gd` → **PASS** (8/8 checks: vampire burns in sun, wolf transforms on full moon, stagger, bite heals +18, wolf rage, wolf drained, frenzy at max Hunger, dash dodges damage).
- **Probe 1** (throwaway script, copied into `game/tests/` only while running, then deleted):
  - Scene stats: 905 nodes, 546 meshes, 532 unique meshes, 53 materials, 8 lights, 158 static bodies. Player 28 meshes, enemy 12.
  - Slow motion: after `perfect_dodge()` followed by a 50 ms hit-stop, `Engine.time_scale` = **0.06 at +400 ms**, and back to 1.0 only at +1000 ms → bug 3.
  - Curb: the player walking and sprinting toward the sidewalk stopped at z=23.16 (curb at 23.5), y≈0 → bug 1.
  - Spawns: 0/2000 overlapped buildings; 9/2000 fell back to <18 m from the player → bug 17.
  - First night: `night_count=1, full_moon=true` → bug 5.
  - Pathing: 12 vampires vs a stationary player for 15 s of game time → **2/12 reached him** → bug 2.
- **Probe 2:** an enemy chasing a player standing on a sidewalk stopped at the curb (1.4 m away, still close enough to hit him). With 12 enemies, the stuck ones reported `is_on_wall()=true` at x=23.1 and x=3.1 (curb faces at 23.5 and 3.5). Jumping does get the player onto the curb.
- **Web export:** `godot --headless --export-release "Web"` succeeded. wasm 35,376,909 bytes (8,041,552 gzipped); pck 44,768 bytes, and it includes `tests/smoke_test.gd`.

**Browser run** (Playwright + Chromium with SwiftShader, no GPU, deviceScaleFactor 1; served with `python3 -m http.server`, then stopped)
- `day_0_title.png`: the title overlay renders; the clock was already at 13:25 (started at 13:12), so the world runs behind the title → bug 6.
- `day_1_start.png`: overcast daytime plaza and the Undercroft ring. Sol reads as a black silhouette with locs and shades barely visible.
- `day_2_sprintdash.png`, `day_3_attack.png`: after sprint, dash and combo; the street and block layout, flat grey daylight.
- `night_1.png` (`?night`): "FULL MOON — The Hollow Pack is turning" on the very first night (bug 5). The floating "THE UNDERCROFT" label overlaps the announcement text. The best-looking scene: neon, lit windows, lamp pools.
- `night_2_fight.png`: a transformed wolf at the lair; the HUD still says "sunlight heals you" at night (bug 11); the drink prompt shows.
- `mobile_1.png` (390x844): the 3D view works, but the HUD text is about 5 px and unreadable (bug 12).
- Console: only the Godot banner and the WebGL 2.0 / Compatibility renderer line, **no errors or warnings**.
- Screenshots are in the session scratchpad (not committed): `/tmp/claude-0/-home-user-daywalker/28ffb1f3-d807-5c0f-af84-a50160a83720/scratchpad/shots/`.

No game code was modified. The only file added to the repo is this report.
