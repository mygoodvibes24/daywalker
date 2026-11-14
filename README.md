# DAYWALKER: BLOOD AND MOON

Open-world action-horror game built in **Godot 4.3**. You are Elijah "Sol" Marrow, a fast, trenchcoat-wearing daywalker hunting vampires and werewolves through the rain-soaked city of Port Vesper.

- Story bible and design: [`STORY_BIBLE.md`](STORY_BIBLE.md)
- Godot project: [`game/`](game/)

## Play it in the browser

Every push builds the game for the web and deploys it to **GitHub Pages** (see `.github/workflows/web.yml`).
One-time setup: repo **Settings → Pages → Source: GitHub Actions**.

### Run locally
```bash
# open game/project.godot in Godot 4.3+ and press F5
# or build the web version:
cd game
godot --headless --export-release "Web" ../build/web/index.html
cd ../build/web && python3 -m http.server 8060   # then open http://localhost:8060
```
The web export uses the single-threaded template, so any static host works (no special headers needed).

### Tests
```bash
cd game
godot --headless --import .
godot --headless -s res://tests/smoke_test.gd   # exits 1 on any failure; CI runs it before every deploy
```

## Main menu and options
The game opens on a **main menu** (`game/scenes/main_menu.tscn`, the project's main scene) over a live 3D scene of Sol's lair in the Undercroft, built from `docs/concept_art/13_main_menu_lair.jpg`: Sol sharpens a silver blade on a whetstone at his workbench under a brass lamp while his assistant **Nia** stands by with a tablet, among the blood fridges, the map table with its red string, candles and the gated subway tunnel. The camera drifts slowly between two framings (with depth of field on desktop).

- **Start** opens **the Undercroft** (the hub, see *The Hunt* below). **Begin the Hunt** there fades out and loads the city (on a background thread with a "Loading..." indicator; synchronously in the browser). The old "click to hunt" title overlay and the endless free-roam mode only appear when `main.tscn` is run directly.
- **Controls** lists every binding in two columns, keyboard / mouse and controller.
- **Options** (saved to `user://settings.cfg` and applied live):
  - **Display:** brightness, window mode (windowed / fullscreen / borderless; windowed or fullscreen in a browser), resolution scale (50-100% 3D render scale), V-Sync, quality preset (Low turns off SSAO, SSIL, SSR and volumetric fog; Medium keeps SSAO and fog), rain on / off.
  - **Controls:** mouse sensitivity, controller look sensitivity, invert Y.
  - **Audio:** master, music and effects volume (the Master, Music and SFX buses).
- The menu works with mouse, keyboard (arrows, Enter, Esc) and controller (D-pad / left stick, **A** to accept, **B** to go back). Left / right changes a slider or a choice.
- **Pause menu:** **Esc** in play pauses the game and frees the mouse: Resume, Options, Controls, Quit to Menu. On a controller, Start is the Coat and B is the dash, so the pause menu is the **Pause** button inside the Coat (or **Back / Share** while the Coat is open).

## Controls
Plug in or pair an Xbox, PlayStation or Switch Pro controller and **press any button** (browsers only detect a controller after a button press).

| Action | Controller | Keyboard / Mouse |
|---|---|---|
| Move | Left stick / D-pad | WASD |
| Camera | Right stick | Mouse |
| Sprint | LT (hold) or L3 | Shift |
| Jump (double jump) | A / Cross | Space |
| Blood Dash (3 charges, phase through enemies) | B / Circle or RB | Right mouse / Q |
| Blade combo (3-hit) | X / Square or RT | Left mouse / J |
| Bite a staggered enemy (red orb above head) | Y / Triangle | E |
| Interact: take loot, open a coffin / crate, keep vigil at the Undercroft (the bite wins when a staggered enemy is in reach) | Y / Triangle | E |
| Drink bagged blood at the Undercroft | LB | F |
| Quick-use slot 1 / 2 (vials, flares) | LB (away from the Undercroft) / R3 | 1 / 2 |
| The Coat (inventory; pauses the game) | Start / Options | Tab or I |
| In the Coat: equip / use / drop / close | A / Y / X / B | Click or Enter / U / X or Del / Tab, I or Esc |
| Pause menu (Resume / Options / Controls / Quit to Menu) | Back / Share inside the Coat, or the Coat's Pause button | Esc |
| Menus: move / accept / back | D-pad or left stick / A / B | Arrows or mouse / Enter or click / Esc |
| Restart after death | Start / Options | R |
| Rain on/off | Back / Share (outside a Hunt) | T |
| **The Hunt:** map (doesn't pause) | Back / Share or touchpad | M |
| **The Hunt:** keep vigil at a chapel, trade with the merchant, pry open a nest coffin | Y / Triangle | E |
| **The Hunt:** skip the Descent | A or X | Space or left mouse |

Controllers vibrate on hits, bites and damage (where the browser supports it).

## The Hunt
The game is played in **Hunts**: short, intense, replayable runs (about 15 minutes; tune them in `game/scripts/hunt/hunt_config.gd`).

1. **The Undercroft (hub).** Start in Sol's lair. Wear up to **3 charms** from your armoury into the Hunt, buy new ones from Nia's contacts with **Sunmarks** (the meta currency every Hunt pays out), and read your record (Hunts, wins, most bosses, best rank, kills). Then **Begin the Hunt**.
2. **The Descent.** Sol enters at a random deployment point on the edge of the city, never the plaza: climbing out of a *Vesper Line* station, bursting up through a storm-drain manhole, or dropping off a roofline with a landing slam while the camera swoops in.
3. **Day 1 → Night 1, Day 2 → Night 2, then the Final Night.** Each day you sprint between **points of interest**, generated per Hunt with a seeded RNG on the city's street crossings:
   - **Velvet Nest:** coffins on a velvet-draped corner. By day it sleeps (a couple of day-servants; pry the coffins open for loot). At night Thralls and a named **Courtier** elite rise.
   - **Hollow Camp:** trailers, barrels and a fire barrel. Pack squatters and a named leader, who all turn when the sun goes down.
   - **Blood Market:** a crate fort of smugglers and their fence, with a guaranteed **Hallowed** find.
   - **Landmark:** a named field boss with a big health bar (*Sir Aurelien, Blood Knight*, *Dame Corvina*, *Old Gristle of the Pines*) guarding an **Eclipse** blade.
   - **Wayside Chapel:** keep vigil here to spend Tithe on a Communion rank (during a Hunt this replaces the Undercroft).
   - **Night Merchant:** Old Ma Celestine's cart sells vials, flares and blades for Tithe.
   Enemies are pre-placed and idle at their sites and rouse when you get close or strike one; only sites within about 60 m are populated (at most 14 active enemies), plus a light trickle of roamers. Clearing a site bursts into Tithe and a loot beam and marks it cleared on the map.
4. **The Red Curfew.** At dusk a wall of blood fog with crimson lightning closes in two stages on tonight's **boss arena** (the Cathedral Steps, Pier Nine Crossing, Velvet Mile Crossing or the Foundry Crossing). Outside it you take ramping damage and the screen bleeds red. The HUD counts down: *"DAY 1 — The Curfew falls in 2:10"*.
5. **The night bosses.** When the Curfew closes the night's boss rises and the wall holds as the arena: **The Hollow Alpha** (Night 1, full moon: leap slams, a howl that calls two wolves, a frenzy below half), **Marcus Crane, the Velvet Fang** (Night 2: chained dash slashes, a blink that lands behind you, fans of blood bolts) and on **the Final Night** at the Undercroft Plaza, **Seraphine's Abomination** (a Pack giant with a Court body fused to its shoulders, in two phases). Every attack telegraphs on the ground and can be dashed through. Bosses pay big Tithe and drop two **Eclipse** items.
6. **Death and results.** You have **1 revive per day**: you get back up at half blood a few metres away, and half your Tithe stays where you fell (walk back for it). Without one the Hunt ends. The results screen shows bosses slain, kills, rank and the Sunmarks earned, then returns you to the Undercroft (or straight into another Hunt).

**What carries over:** charms you wear from the hub, your Sunmarks and record, and every charm you carry home (it joins the armoury). **What doesn't:** rank, Tithe, Vows, blades and vials start over every Hunt (free roam still uses `user://save.json`; Hunts save only `user://hunt_meta.json`).

**HUD:** a compass strip with every site, the arena and your Lost Tithe; the phase and countdown under it; revive charges and site / boss / kill tallies on the right; the boss bar at the bottom. **M** (pad Back) opens the map: the blocks, every site (cleared ones struck through), the Curfew now and where it closes next, the arena and your arrow.

**Debug:** `--shorthunt` (command line, after `--`) or `?shorthunt` (web URL) runs a ~3-minute Hunt with weaker bosses; `--hunt` / `?hunt` starts a Hunt from `main.tscn` directly; `--seed=N` fixes the layout.

Code: `game/scripts/hunt/` (`hunt_director.gd` run state machine, `hunt_config.gd` data, `poi.gd` / `poi_spawner.gd` / `poi_dressing.gd`, `curfew_ring.gd`, `deploy.gd`, `elite.gd`, `hunt_meta.gd`, `hub_panel.gd`, `bosses/*.gd`) and `game/scripts/ui/` (`hunt_hud.gd`, `compass.gd`, `map_screen.gd`, `results_screen.gd`, `merchant_ui.gd`, `poi_icons.gd`). `main.gd` only carries a few `HUNT HOOK` lines.

## What's in the prototype
- **Day/night cycle** (4 min). By day vampires burn and the Pack walks among you as civilians; at night the Velvet Court hunts and wolves transform. Every 3rd night is a **full moon**, when wolves get bigger and meaner.
- **The Bite.** Knock an enemy down to 25% HP to stagger it, then bite to heal. Human, vampire and wolf blood each have different effects.
- **Hunger meter.** Biting raises it. Low hunger = *Daywalker* (sunlight heals). High = *Nightborn* (+25% damage). Max = **Frenzy**.
- **Perfect dodge.** Dash through (or out of) an enemy's strike to trigger bullet-time and refund a dash. Strikes are committed when the wind-up starts, so you can also just sidestep them.
- **Enemies hunt properly.** They path around buildings, and only two attack at once while the rest circle you.
- **The Undercroft**, Sol's lair entrance in the cathedral plaza, with a blood bank that restocks at sunrise.

## Progression
- **Tithe** is the blood-essence currency. Every kill bursts into red motes that fly to you when you're close (vampire 8, Pack civilian 12, werewolf 25, full-moon wolf 40; draining with a bite pays 50% more). Your total is on the HUD.
- **Communion ranks.** Offer Tithe at the Undercroft (**Keep Vigil**) to rise a rank, up to 15. Rank 2 costs 25 Tithe and the price climbs steadily. Every rank adds max blood, damage, dash recharge and bite healing.
- **Vows.** Each new rank offers three random Vows (17 in all), passive perks such as *Crimson Wake* (your dash leaves a burning blood trail), *Sidestep Sacrament* (perfect dodges heal), *Communion Ward* (bites make you untouchable for a moment), *Crescent Rite* (the third combo hit throws a blood wave), *Sunward* and *The Long Night*.
- **Loot.** Kills drop items more often at night and on full moons, and 20 **cold coffins and smuggler crates** on the sidewalks restock at sunrise. Every dropped item stands in a light beam coloured by rarity: **Street** (white), **Blooded** (green), **Hallowed** (blue) and **Eclipse** (purple with a gold core). Eclipse items carry unique effects.
- **The Coat** holds 24 items plus 1 blade, 3 gris-gris charms and 2 quick-use slots. There are 35 items: 15 blades (sabers, machetes, cane-swords, cleavers, longblades, kukris; each has its own damage, speed, reach and a special such as silver against wolves, sun-steel against vampires or lifesteal), 17 charms (gris-gris, rosaries, fangs, medals, bones, candles, mirrors), and blood vials and Dawn Flares (a UV burst that burns vampires) for quick use.
- **Saving.** Rank, Tithe, Vows and the Coat are saved to `user://save.json` when you rank up, change equipment and return to the lair. If you die you keep your progression, but half your carried Tithe stays where you fell under a crimson beam. Walk back to it to recover it. Die again first and it's gone.
