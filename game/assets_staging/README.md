# Asset staging, round 3

Generated, prepared and checked assets waiting for an integration round. Nothing in the game references them yet.
Spend and job ids: `LEDGER.md` (185.65 of the 195-credit cap).

| Folder | What | Index |
|---|---|---|
| `creatures/` | 8 skeleton-only clips: 5 werewolf (feral run, heavy swipe, pounce, roar, heavy death), 3 vampire (lunge, claw combo, backflip) | `creatures/manifest.json` |
| `bosses/marcus_crane/` | Marcus Crane mesh (PBR), skinned rig, 3 clips, 4 reference views | `manifest.json`, `../CREDITS.md` |
| `bosses/abomination/` | Seraphine's Abomination mesh (PBR), skinned rig, 3 clips | `manifest.json` |
| `bosses/hollow_alpha/` | the werewolf plus the new werewolf clips at 1.35x (no new files) | `manifest.json` |
| `faces/` | Nia head-scan captures and the raw reconstruction, draft `scan.json` (`.gdignore`: Python build sources) | `faces/README.md` |
| `textures/` | 18 seamless materials + 2 alpha foliage cards, albedo/normal/roughness at 1024 px | `textures/manifest.json` |
| `props/` | mausoleum, cast-iron gazebo, wrecked fishing boat, Victorian street clock | `props/manifest.json` |
| `audio/` | 2 looping boss themes and 7 creature SFX (OGG) | `audio/manifest.json` |

## Import settings (already in the committed `.import` files)
- Every texture, including the ones Godot extracted from the GLBs (`<model>_0/1/2.jpg`: albedo,
  metallic-roughness, normal), imports as **Lossy (WebP)** with mipmaps and `detect_3d/compress_to=0`; normal maps
  set `compress/normal_map=1`. A test import in Godot 4.3 produced no VRAM textures.
- The boss themes import with `loop=true`.
- The folders holding `rigged/` skinned meshes, Marcus's reference views and the face sources carry `.gdignore`:
  they are read with GLTFDocument or Python, as `game/tools/build_enemy_anims.gd` reads `characters/*/rigged/`.

## Orientation and units
All models face +Z, stand on y=0 and are real size (Marcus 1.88 m, Abomination 2.8 m). Clip GLBs hold the Meshy
24-bone skeleton in centimetres, the same bone names as Sol and the enemies; each clip shares the skeleton of the
mesh it was rigged on.
