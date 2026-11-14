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

- **Start** fades out and loads the city (on a background thread with a "Loading..." indicator; synchronously in the browser). The game begins at once; the old "click to hunt" title overlay only appears when `main.tscn` is run directly.
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
| Rain on/off | Back / Share | T |

Controllers vibrate on hits, bites and damage (where the browser supports it).

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
