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

## Controls
| Action | Key |
|---|---|
| Move / Sprint | WASD / Shift |
| Jump (double jump) | Space |
| Blood Dash (3 charges, phase through enemies) | Right mouse / Q |
| Blade combo (3-hit) | Left mouse / J |
| Bite a staggered enemy (red orb above head) | E |
| Drink bagged blood at the Undercroft | F |
| Restart after death | R |

## What's in the prototype
- **Day/night cycle** (4 min). By day vampires burn and the Pack walks among you as civilians; at night the Velvet Court hunts and wolves transform. Every 3rd night is a **full moon**, when wolves get bigger and meaner.
- **The Bite.** Knock an enemy down to 25% HP to stagger it, then bite to heal. Human, vampire and wolf blood each have different effects.
- **Hunger meter.** Biting raises it. Low hunger = *Daywalker* (sunlight heals). High = *Nightborn* (+25% damage). Max = **Frenzy**.
- **Perfect dodge.** Dash through an attack to trigger bullet-time and refund a dash.
- **The Undercroft**, Sol's lair entrance in the cathedral plaza, with a blood bank that restocks at sunrise.
