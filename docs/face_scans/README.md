# Face scans

A simulated photogrammetry pipeline for the hero faces. A real scan rig (dozens of synchronised cameras,
cross-polarised flashes) is replaced by generated photos, but the steps after the capture are the same as
for a scanned actor: reconstruct, project the photos back onto the mesh, bake, shade.

## The record (`sol/`)

| file | what |
| --- | --- |
| `s01_front.jpg` ... `s10_below.jpg` | the capture session: one person, neutral face, flat shadowless light, grey backdrop, 85 mm look. Front, +-30, +-60, +-90 degrees (s02/s04/s06 = camera on his left), back, slightly above and below. Downscaled to 1024 px. |
| `plate_skin.jpg`, `plate_beard.jpg` | close-up plates: cheek / forehead pores and beard stubble |
| `scan.json` | the configuration the projection tool runs from (views, angles, priorities, eye landmarks, placement) |

Sol has no glasses in the capture: his round sunglasses are a separate procedural mesh fitted to the face
by `game/tools/build_sol_modular.gd`.

## Pipeline

1. **Capture.** Generated with Higgsfield (GPT Image 2.6) on 2026-11-15, each shot referencing the design
   reference and the front capture for identity. The +60 degree shot was regenerated once (the first was rejected
   by the content filter).
2. **Reconstruction.** Front, left profile, back and right profile, masked below the neck base, went to Tripo
   H3.1 multiview-to-3D (detailed geometry, 200k faces, standard texture, no PBR) on 2026-11-18. The raw result
   is `game/assets/characters/sol/sol_scan_head_raw.glb` (a build source; not exported).
3. **Projection** (`game/tools/project_face_texture.py`, run as
   `python3 game/tools/project_face_texture.py docs/face_scans/sol/scan.json`; needs numpy, pillow, scipy,
   trimesh, numba, xatlas, fast_simplification, embreex, networkx):
   - the raw mesh is welded across its UV seams, oriented, decimated to 36k triangles and unwrapped: the face
     (front-facing skin between the ears, brow to chin) is one planar chart in a strip of its own at
     5.7 px/mm; hair, ears and neck are charted by xatlas next to it (a 2048 x 1328 atlas);
   - one camera per photo: the nominal angle is known, zoom, offset and a few degrees of yaw / pitch / roll
     are fitted by matching the mesh silhouette to the photo's foreground (IoU 0.89 to 0.96). Frontal
     views have tight yaw priors, since a silhouette cannot tell their yaw;
   - every texel of the game mesh is projected into every photo; it counts only where it is the nearest
     surface (z-buffer test), weighted by cos^5 of the viewing angle, feathered away from silhouette
     edges and the neck crop, and then sharpened toward the best view (view cosine plus a per-view priority,
     front first). Generated photos do not agree perfectly with each other, and averaging them ghosts the
     eyes and lips; picking the best view per texel keeps them sharp;
   - per-photo RGB gains are matched to the front photo first, the under-jaw neck is matched to the
     cheeks, texels no photo sees take the reconstruction's own texture, and the seams are dilated;
   - bakes from the full 195k-triangle scan onto the game mesh: a tangent-space normal map (plus stubble
     relief from the beard plate where the beard is) and ambient occlusion; a roughness map from regions (oilier
     T-zone and lips, matte cheeks, rough beard and hair) and a cavity term; a detail mask; a tiling detail
     normal made seamless from the skin plate;
   - the head is placed in skeleton space by its eyes (64 mm interpupillary distance, eye line where the
     glasses expect it), cut at the collar, and written out with `sol_scan_head_eyes.json`.
4. **Shading** (`_skin_material()` in `build_sol_modular.gd`): StandardMaterial3D, albedo and ORM, a
   normal map, and the pore detail normal on UV2 (14 repeats per UV unit, masked off in hair and beard).
   On Forward+ it adds subsurface scattering (skin mode, reddish transmittance); the Compatibility renderer
   (web, mobile) ignores SSS, so the albedo is de-lit and toned down (no orange) and a low rim term stands
   in for the soft forward scatter on both renderers.
5. **Eyes.** A sphere behind each scanned eye whose front cap pokes 1.6 mm through the scanned eye
   surface: inside the lids you see a procedural iris (pupil, radial fibres, limbal ring) under a clear-coat
   cornea that gives the wet highlight; the eye whites around it are the projected photo. Parented to the
   head bone.
6. **Rig.** `build_sol_modular.gd` (`USE_SCANNED_HEAD`) loads the head, pushes its neck out where the
   body's own neck would show, tucks the open neck edge into the collar and skins it like the old bust (all
   Head above the jaw, blending into the body's neck and spine weights below), then refits the glasses.

Textures import as Lossy (WebP): 2048 px for the albedo, 1024 px for the normal and ORM maps, 512 px for the
detail maps. Never VRAM: the web build cannot load VRAM-compressed character textures.

## Rebuild

```
python3 game/tools/project_face_texture.py docs/face_scans/sol/scan.json
cd game && godot --headless --import . && godot --headless -s res://tools/build_sol_modular.gd
```
