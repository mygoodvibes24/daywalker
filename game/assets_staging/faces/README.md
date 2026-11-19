# Faces (asset round 3)

Staged inputs for the face-scan pipeline in `docs/face_scans/README.md`. This folder has a `.gdignore`:
these are build sources for `game/tools/project_face_texture.py` (Python), not Godot resources.

## Nia (`nia/`)
- **Capture** (GPT Image 2.6, 2026-11-18/19), identity from the menu design reference (`nia_ref.png`) and then
  from the front capture: `n01_front` (medium quality), `n02_l30`, `n03_r30`, `n06_l90`, `n07_r90`, `n08_back`
  (low quality), 819 x 1024. Camera-on-her-left views (`l`) face image-left, as in Sol's record. Neutral face,
  no glasses (her glasses should be a separate procedural mesh, as Sol's sunglasses are), hair in a high bun with
  cornrows, plain charcoal t-shirt (a bare-shoulder prompt was rejected by the content filter, so the neck crop
  must cut above the collar). The ±60 degree, above and below views were skipped to stay inside the 14-credit cap.
- **Reconstruction:** front, left profile, back, right profile went to Tripo H3.1 multiview-to-3D
  (detailed geometry, 200k faces, no texture) = `nia_scan_head_raw.glb` (193k triangles, faces +X like Sol's raw
  scan, so `scan_yaw` is -90). `raw_mesh_check.jpg` shows it from 4 sides.
- **Next step:** move the jpgs to `docs/face_scans/nia/`, the mesh to `game/assets/characters/nia/`, check
  `scan.json` (a draft: `eyes_px` was measured by eye; `placement` must match Nia's body rig), then run
  `python3 game/tools/project_face_texture.py docs/face_scans/nia/scan.json`.

## Sol re-capture (not done)
The ±30 degree re-capture did not fit: Nia's capture and reconstruction used 13.75 of the 14 credits.
It costs about 0.5-1 credit (two GPT Image 2.6 shots referencing `docs/face_scans/sol/s01_front.jpg`).
