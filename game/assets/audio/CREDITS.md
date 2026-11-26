# Audio credits

All audio in `game/assets/audio/` was generated for Daywalker through the Higgsfield platform on **2026-11-14**, then trimmed, peak-normalised and converted to OGG Vorbis with ffmpeg (voice: mono 22.05 kHz; SFX: mono 44.1 kHz, rain and thunder stereo; music: stereo 44.1 kHz).

| Folder | Higgsfield model | Files |
|---|---|---|
| `voice/` | `elevenlabs_v4` (Eleven v4, preset voices) | 60 dialogue lines, ids in `game/data/dialogue.json` |
| `music/` | `elevenlabs_music_v2` (ElevenLabs Music v2, instrumental) | `menu_lair` (90 s), `explore` (70 s), `combat` (55 s, street fights); boss music: see Round 4 |
| `sfx/` | `mirelo_text_to_audio` (Mirelo SFX) | 29 sounds (+2 made with ffmpeg, see below) |

## Voices (Higgsfield preset voices)

| Character | Preset voice | voice_id |
|---|---|---|
| Sol | Brooks | `c2acff45-84b2-4974-892d-89fa2d4e5598` |
| Nia | Naomi | `caeba733-3c17-43db-863e-69c7025512cd` |
| Count Lucien | Alistair | `d9d5c263-f84e-4752-97b5-3750fcc6fd2f` |
| Marcus Crane | Julian | `95429266-c0ac-4137-a209-63b8812b0f23` |
| Seraphine | Vesper | `c3204739-4084-41a3-9dc5-c805b307ec18` |
| Detective Reyes | Marisol | `75e72cd5-011b-4130-a474-e8b1ab341f04` |
| Vampire (street) | Caspian | `ef70cc83-3015-4bad-9359-0ea968c43ec0` |
| Velvet Court courtier | Sloane | `b57b22a0-f287-405b-bc82-6f08f5e6bb1f` |

The Hollow Alpha and the werewolves have no voice: they use the `wolf_growl`, `wolf_howl` and `wolf_transform` sound effects.

## Music prompts (instrumental)
- **menu_lair:** brooding gothic noir theme for a crypt lair; slow walking upright jazz bass, mournful solo cello, brushed drums, distant organ pad, rain and far thunder; minor key, 60 BPM, loopable.
- **explore:** loopable night ambience; low drones, sparse muted piano, sub-bass pulses, a distant lonely saxophone, soft rain; no percussion.
- **combat:** loopable combat music; driving cello ostinato, taiko and industrial drums, distorted bass, brass stabs, dark choir-like pads, 140 BPM.

## Sound effects
sword_swing_1/2, sword_hit_1/2, bite, blood_dash, perfect_dodge, level_up, loot_pickup, loot_rare_hum, tithe_collect, wolf_transform, wolf_growl, wolf_howl, vamp_hiss, vamp_burn, death, rain_loop, thunder, step_wet_1/2, ui_hover, ui_click.

## Round 2 additions (2026-11-18)
Generated on Higgsfield (7.4 credits), processed as above.
- **Voice (Nia, Naomi):** re-recorded `hunt_deploy_1`, `boss_alpha_intro` and `hunt_extract` so they match the game (no "three marks", the Alpha is male, no extraction); new `intro_brief_1`, `intro_brief_2`, `intro_brief_3` (the first-Hunt briefing). `poi_cleared_1` was re-keyed as `poi_cleared_nest` (same audio).
- **SFX (Mirelo):** boss_slam (decay envelope and low boost added), boss_swipe, blood_bolt, boss_blink, curfew_drone (crossfaded into a 3 s loop), manhole_clank (+19 dB, it came back very quiet).
- **Made with ffmpeg:** the Mirelo `parry_clang` and `land_thud` generations came back near silent (peaks at -30 and -35 dB), so `parry_clang` is `sword_hit_1` pitched up 25% with three decaying steel partials (2.35, 3.72, 5.23 kHz), and `land_thud` is the low end (below 260 Hz) of `boss_slam`, cut to 0.6 s.

## Round 3 additions (2026-11-18/19)
Generated on Higgsfield (9.9 credits; job ids in `docs/assets_r3/LEDGER.md`, prompts in `docs/assets_r3/audio_manifest.json`).
- **Boss themes (ElevenLabs Music v2):** `boss_marcus` (velvet jazz menace) and `boss_abomination` (taiko, anvils, wordless choir). Replaced in round 4.
- **Creature SFX (Mirelo):** `werewolf_roar`, `claw_swipe` (+16 dB), `pounce_whoosh`, `vampire_hiss` (a second `vamp_hiss` variant), `vampire_lunge_whoosh`, `boss_slam_impact`, `body_fall`; timed to the round-3 creature clips in `audio.gd`.

## Round 4: vampire-hunter hip-hop boss music (2026-11-26)
Generated on Higgsfield with `elevenlabs_music_v2` (`force_instrumental`, 38 s each, 14.58 credits for the shipped set; an earlier Japanese-flavoured set, 25.25 credits, was dropped at the owner's request and is not used; job ids, prompts and loop points in `docs/assets_r4/LEDGER.md`). Original instrumentals in one style: late-90s dark vampire-hunter action music, with hard hip-hop beats (boom-bap and breakbeat, distorted 808s, gritty stabs) fused with industrial synths and acid or techno leads, plus a thin horror-orchestra layer. Loop-cut on whole bars with a 0.6 s equal-power seam, no fade-out tails, OGG Vorbis q5 stereo 44.1 kHz, imported with loop=true.

| File | Plays in | Character | Length |
|---|---|---|---|
| `music/boss_marcus.ogg` | Marcus Crane, the Velvet Fang | sleek blood-club rave on a hip-hop backbone, acid lead, 95 BPM | 32.8 s |
| `music/boss_abomination.ogg` | Seraphine's Abomination | the heaviest: distorted industrial stomp, half-time 90 BPM | 29.4 s |
| `music/boss_knight.ogg` | Cassius Vane, Lucien's Blood Knight | sharp driving breakbeat duel, steel-like metal hits, 100 BPM | 31.3 s |
| `music/boss_hollow.ogg` | The Hollow Alpha | feral tribal-industrial drums, growling 808, 92 BPM | 31.3 s |
| `music/boss_shared.ogg` | field bosses and any boss without a theme | solid hunter theme: boom-bap, industrial arpeggio, techno pulse, 95 BPM | 30.3 s |
| `music/rival_crowe.ogg` | Silas Crowe, the Pale Daywalker (Undercroft duel) | cold minimal techno-hip-hop, 90 BPM | 32.0 s |
