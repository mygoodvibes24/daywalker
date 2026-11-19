# Boss assets: credits and provenance (asset round 3, 2026-11-18)

All generated with Higgsfield for this project; original designs, no third-party likeness.

| Asset | Generator | Credits | Job id |
|---|---|---|---|
| Marcus Crane reference views (front, left, back, right) | GPT Image 2.6, medium quality; the side and back views use the front as a reference image | 2.0 | f73917fe, 3a5d05ec, 85b0cb56, 60d3a3df |
| Marcus Crane mesh `marcus_crane/marcus_crane.glb` | Tripo H3.1 multiview-to-3D, detailed geometry and texture, PBR, align_image, 50k face limit | 18 | 57fd8333-3c96-4cdb-8e10-6ca23801bcdc |
| Marcus rig + 3 clips | Higgsfield 3D Rigging (Meshy), library clips 202, 216, 185 | 24 | 738f768b, e45a9717, 3399b13a |
| Abomination mesh `abomination/abomination.glb` | Tripo text-to-3D, standard, PBR, 40k face limit | 5 | 8cc4c636-1822-4698-8f14-bb47f2c3db7f |
| Abomination rig + 3 clips | Higgsfield 3D Rigging (Meshy), library clips 127, 389, 388 | 24 | aa7edcc7, 45ba79c8, aa095790 |
| The Hollow Alpha | reuses the werewolf and the creature clips | 0 | - |

Bosses total: 73 of the 80-credit sub-cap.

Processing: meshes turned to face +Z and scaled with `normalize_glb.gd` (a GLTFDocument variant of
`game/tools/normalize_part.gd`, in the round-3 scratchpad), uploaded with `media_upload`, rigged by URL;
rig downloads stripped with `game/tools/strip_rig_glb.gd` (`anim` for clips, `mesh` for the skinned body).
The animation library previews (`previews_chosen.jpg`) are Meshy's own reference renders, kept for study only.
