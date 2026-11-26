# Asset round 4 ledger: boss music (vampire-hunter hip-hop)

Owner's request: hip-hop music in the boss fights. The direction changed mid-round: first a
Japanese-flavoured boom-bap brief, then the owner's correction: "a Blade-type feel, not Japanese",
and no samurai or Japanese flavour of any kind. The shipped tracks are six original instrumentals
in one style: late-90s dark vampire-hunter action music, with hard hip-hop beats (boom-bap and
breakbeat, distorted 808s, gritty stabs) fused with industrial synths and acid or techno leads,
plus a thin horror-orchestra layer. The prompts describe the style only. They name no film, song,
artist or soundtrack.

**Credits:** 39.83 in all (cap: 40), confirmed against `transactions`:
- 25.25 on the first, Japanese-style set, which was dropped and is not used: seven jobs, including one Abomination retake.
- 14.58 on the shipped set: six jobs at 38 s and 2.43 credits each. The 38 s length was set by the budget that remained.

The account balance fell further over the same period (198.45 to 142.62) because of two 8-credit
"3D Rigging" jobs that other agents ran in parallel. They are not part of this round.

## Shipped set (style 2: vampire-hunter hip-hop, industrial and techno)
| # | Track | Model | Settings | Credits | Job id | Result |
|---|---|---|---|---|---|---|
| 11 | `boss_marcus` | elevenlabs_music_v2 | 38 s, force_instrumental | 2.43 | 624ef7e4-fa84-4f70-ba4b-0679c97fbf80 | ok |
| 12 | `boss_abomination` | elevenlabs_music_v2 | 38 s, force_instrumental | 2.43 | a6ca6d6e-0613-41d4-9eed-6042064d70dd | ok |
| 13 | `boss_knight` | elevenlabs_music_v2 | 38 s, force_instrumental | 2.43 | f9db70ae-daee-45ce-9b4e-915c18d111a8 | ok |
| 14 | `boss_hollow` | elevenlabs_music_v2 | 38 s, force_instrumental | 2.43 | af4d7920-bda0-4e8a-83a7-4199f7893100 | ok (fade-out tail cut) |
| 15 | `boss_shared` | elevenlabs_music_v2 | 38 s, force_instrumental | 2.43 | f4d172de-c295-4b9d-9992-a1ab3b813cdc | ok (fade-out tail cut) |
| 16 | `rival_crowe` | elevenlabs_music_v2 | 38 s, force_instrumental | 2.43 | 3bcb032f-64c8-4d19-b70e-e14cd38dfa29 | ok |

## Dropped set (style 1: Japanese-flavoured boom-bap; the owner rejected this style, so none of it is used)
| # | Track | Settings | Credits | Job id | Result |
|---|---|---|---|---|---|
| 1 | boss_marcus | 56 s | 3.59 | f1b5330b-7c37-49c7-a253-ea76def1431a | rejected (style change) |
| 2 | boss_abomination | 56 s | 3.59 | 7fc7ef81-0066-417f-8ca6-7a623038496a | rejected: 11 s quiet intro and a fade left only a 39.5 s loop |
| 3 | boss_knight | 56 s | 3.59 | e619b42a-45aa-47f4-832f-03b7c7a646db | rejected (style change) |
| 4 | boss_hollow | 56 s | 3.59 | 0759e342-2237-4d7e-941b-0c9bda3e27ad | rejected (style change) |
| 5 | boss_shared | 56 s | 3.59 | 8d0e83b7-418e-4016-bbd1-8aface47e698 | rejected (style change) |
| 6 | rival_crowe | 56 s | 3.59 | cc5634f6-9bd2-442c-9cac-1c86f5b9514c | rejected (style change) |
| 7 | boss_abomination retake | 58 s | 3.71 | d05f8522-6d3a-4af2-87dc-e22c41392198 | rejected (style change) |

Several submissions were refused by the rate limit (at most 2 concurrent jobs). Those refusals cost
nothing, and the jobs were resubmitted once earlier jobs finished.

Result URLs: `https://d8j0ntlcm91z4.cloudfront.net/user_3M3cbVYOpQkCAbZXwwBloXVahos/hf_20261126_<time>_<job id>.mp3`.

## Processing
1. Start from the MP3 output.
2. Find the tempo from the onset envelope's autocorrelation, searching near the prompt's BPM, and lay a bar grid over the track.
3. Pick a loop of whole bars whose last 4 s best match the 4 s around its start, preferring the longest near-best seam.
4. Equal-power crossfade the last 0.6 s of the loop with the 0.6 s just before its start, so the end runs straight into the first bar.
5. Normalise to a peak of 0.93.
6. Encode as OGG Vorbis q5, 44.1 kHz stereo, imported with loop=true.

No track keeps a fade-out tail. The levels are set in `MUSIC_DB` so that each track lands near the
loudness of the old boss themes, about -17.5 LUFS after gain.

| Track | BPM (grid) | Loop (source s) | Bars | Length | OGG size | Loudness | MUSIC_DB |
|---|---|---|---|---|---|---|---|
| boss_marcus | 95.1 | 2.54-35.35 | 13 | 32.8 s | 643 KB | -11.9 LUFS | -5.5 |
| boss_abomination | 89.9 | 4.66-34.01 | 11 | 29.4 s | 577 KB | -12.7 LUFS | -4.5 |
| boss_knight | 99.9 | 3.29-34.55 | 13 | 31.3 s | 592 KB | -12.6 LUFS | -5.0 |
| boss_hollow | 92.1 | 2.62-33.92 | 12 | 31.3 s | 624 KB | -12.8 LUFS | -4.5 |
| boss_shared | 95.1 | 4.12-34.40 | 12 | 30.3 s | 574 KB | -13.7 LUFS | -4.0 |
| rival_crowe | 89.9 | 3.77-35.77 | 12 | 32.0 s | 661 KB | -13.3 LUFS | -4.0 |

The loops run about 30 s, shorter than the 50-60 s first planned, because the budget left after the
style change paid for 38 s per track. Nobody has listened to them yet, because there is no audio
output here. Before calling them final, listen for vocal-like textures and check the seams. Every
request was sent with `force_instrumental`. If a track has to be lengthened later, a 56 s take costs
3.59 credits.

## Prompts (shipped set)
11. **boss_marcus:** Original instrumental, no vocals, no lyrics. Late-90s dark vampire-hunter action music: a sleek blood-club rave with a hard hip-hop backbone. 95 BPM boom-bap drums, distorted 808 sub-bass, gritty sampled stabs, with a 140 BPM techno layer on top: pulsing acid synth lead, dark industrial arpeggio, metallic percussion, a thin ominous choir pad and low strings. Glossy, menacing underground night-club energy. Full intensity from the very first downbeat to the last bar: no intro, no breakdown, no fade-out; one steady loopable groove.
12. **boss_abomination:** Original instrumental, no vocals, no lyrics. Late-90s dark vampire-hunter action music at its heaviest: a brutal industrial stomp with a half-time hip-hop beat at 90 BPM. Massively distorted 808 sub-bass, crushing kick and snare, clanging metal-factory percussion, grinding saw-wave industrial synths, aggressive electronic hits and noise bursts, a dark horror-orchestra layer of low brass and strings with a menacing choir pad. Monstrous, relentless, combat-ready. Full intensity from the very first downbeat to the last bar: no intro, no breakdown, no fade-out; one steady loopable groove.
13. **boss_knight:** Original instrumental, no vocals, no lyrics. Late-90s dark vampire-hunter action music for a sword duel: a sharp, driving breakbeat at 100 BPM with hip-hop swagger, chopped funk-style breaks, distorted 808 sub-bass, gritty sampled orchestral stabs, fast dark industrial synth arpeggio, a stabbing acid rave lead, metallic percussion hits like clashing steel, tense low strings underneath. Precise, aggressive and punchy. Full intensity from the very first downbeat to the last bar: no intro, no breakdown, no fade-out; one steady loopable groove.
14. **boss_hollow:** Original instrumental, no vocals, no lyrics. Late-90s dark vampire-hunter action music against a werewolf pack leader: feral tribal-industrial drums, pounding floor toms and metal hits over a half-time hip-hop beat at 92 BPM, a growling distorted 808 bass that snarls and slides, a rolling dark techno pulse at 138 BPM, aggressive electronic hits, howling filtered synth sweeps, low horror strings and a dark choir pad. Savage and primal, combat-ready. Full intensity from the very first downbeat to the last bar: no intro, no breakdown, no fade-out; one steady loopable groove.
15. **boss_shared:** Original instrumental, no vocals, no lyrics. Late-90s dark vampire-hunter action theme for a lone hunter in a rainy gothic city at night: solid heavy boom-bap drums at 95 BPM, distorted 808 sub-bass, gritty sampled stabs, a dark industrial synth arpeggio and a driving techno pulse layered on top, metallic percussion, an ominous low-string and choir layer for tension. Determined, punchy and combat-ready with blood-rave energy. Full intensity from the very first downbeat to the last bar: no intro, no breakdown, no fade-out; one steady loopable groove.
16. **rival_crowe:** Original instrumental, no vocals, no lyrics. Late-90s dark vampire-hunter music for a cold mirror-match duel in a flooded crypt: minimal techno-hip-hop, a hard dry hip-hop kick and snare at 90 BPM with a steady minimal techno hi-hat and pulse at 135 BPM feel, a deep sustained 808 sub-bass, a sparse cold repeating synth arpeggio, clicking metallic percussion, a faint icy pad and a low string drone. Restrained, tense and precise. Steady from the very first downbeat to the last bar: no intro, no breakdown, no fade-out; one loopable groove.

## Where each plays (`game/scripts/audio/audio.gd`)
| Fight | Hook | Music context |
|---|---|---|
| Marcus Crane (night boss `marcus`) | `hunt_director._spawn_boss` -> `Audio.set_boss(true, id)` | `boss_marcus` |
| Seraphine's Abomination (final boss `abomination`) | same | `boss_abomination` |
| Cassius Vane, the Blood Knight (night boss `knight`) | same | `boss_knight` |
| The Hollow Alpha (night boss `alpha`) | same | `boss_hollow` |
| Field bosses (the Landmark guardians Sir Aurelien, Dame Corvina and Old Gristle) and any boss without a theme | `boss_base.wake()` -> `Audio.engage(self, "boss")` | `boss` = `boss_shared` |
| Silas Crowe, the Pale Daywalker (Undercroft Depths) | `undercroft_rival._taunt()` -> `Audio.engage(self, "rival_crowe")` | `rival_crowe` |

Each theme crossfades in over 1.2 s when its fight starts. The music crossfades back to combat
(enemies near) or explore when any of these happens:
- the night boss dies (`set_boss(false)`);
- a field boss or the rival dies;
- the rival resets because Sol left;
- Sol moves more than 40 m from a field boss;
- Sol falls.

Both music players are on the Music bus (`default_bus_layout.tres`), so the Music volume slider
applies. The old `combat.ogg` stays, because it is still the street-combat track. The round-3 boss
themes were replaced in place under the same file names.
