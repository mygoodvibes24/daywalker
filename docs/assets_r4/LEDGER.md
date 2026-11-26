# Asset round 4 ledger: boss music (hip-hop)

Owner's request: "When he's in the boss fight, change the music to a hip-hop beat." Six original
instrumentals: dark boom-bap / half-time trap with Japanese instruments (shamisen, koto, taiko,
shakuhachi) over gothic synths and strings. The prompts describe the style only; they name no song,
artist or soundtrack.

Balance: 198.45 credits before, 176.91 after. **Spent: 21.54 credits** (cap: 30). No retries.

| # | Track | Model | Settings | Credits | Job id | Result |
|---|---|---|---|---|---|---|
| 1 | `boss_marcus` | elevenlabs_music_v2 | 56 s, force_instrumental | 3.59 | f1b5330b-7c37-49c7-a253-ea76def1431a | ok (10.7 s quiet intro skipped: the loop starts on the drop) |
| 2 | `boss_abomination` | elevenlabs_music_v2 | 56 s, force_instrumental | 3.59 | 7fc7ef81-0066-417f-8ca6-7a623038496a | ok (11 s quiet intro and the fade-out tail cut: 14-bar loop) |
| 3 | `boss_knight` | elevenlabs_music_v2 | 56 s, force_instrumental | 3.59 | e619b42a-45aa-47f4-832f-03b7c7a646db | ok |
| 4 | `boss_hollow` | elevenlabs_music_v2 | 56 s, force_instrumental | 3.59 | 0759e342-2237-4d7e-941b-0c9bda3e27ad | ok (fade-out tail cut) |
| 5 | `boss_shared` | elevenlabs_music_v2 | 56 s, force_instrumental | 3.59 | 8d0e83b7-418e-4016-bbd1-8aface47e698 | ok (a 4 s near-silent break at 31-35 s was spliced out on the bar grid, 2 bars) |
| 6 | `rival_crowe` | elevenlabs_music_v2 | 56 s, force_instrumental | 3.59 | cc5634f6-9bd2-442c-9cac-1c86f5b9514c | ok |

Two first submissions of #3 and #4 were refused by the rate limit (max 2 concurrent jobs, no charge)
and resubmitted once the first jobs finished.

Result URLs: `https://d8j0ntlcm91z4.cloudfront.net/user_3M3cbVYOpQkCAbZXwwBloXVahos/hf_20261126_<time>_<job id>.mp3`.

## Processing
MP3 (56 s) -> tempo from the onset envelope's autocorrelation near the prompt's BPM, bar grid anchored
on the drop -> a loop of whole bars chosen where the 4 s around its end best match the 4 s around its
start -> the last 0.6 s of the loop equal-power crossfaded with the 0.6 s just before its start (so the
end runs straight into the first bar) -> peak 0.93 -> OGG Vorbis q5, 44.1 kHz stereo, imported with
loop=true. No fade-out tails.

| Track | BPM | Loop (source s) | Bars | Length | OGG size | Loudness | MUSIC_DB |
|---|---|---|---|---|---|---|---|
| boss_marcus | 89.9 | 10.66-53.34 | 16 | 42.7 s | 853 KB | -15.1 LUFS | -2.5 |
| boss_abomination | 85.1 | 11.31-50.82 | 14 | 39.5 s | 752 KB | -14.1 LUFS | -3.5 |
| boss_knight | 94.0 | 2.87-53.93 | 20 | 51.1 s | 967 KB | -14.9 LUFS | -2.5 |
| boss_hollow | 88.0 | 2.73-51.80 | 18 | 49.1 s | 941 KB | -13.6 LUFS | -4.0 |
| boss_shared | 92.1 | 3.28-52.79 minus 30.00-35.21 | 17 | 44.3 s | 877 KB | -13.0 LUFS | -4.5 |
| rival_crowe | 85.0 | 3.54-51.52 | 17 | 48.0 s | 896 KB | -13.5 LUFS | -4.5 |

Not checked by ear (no audio output here): listen for stray vocal-like textures and the seams before
calling it final. Every request was sent with `force_instrumental`.

## Prompts
1. **boss_marcus:** Original dark cinematic boom-bap hip-hop instrumental, 90 BPM, no vocals, no lyrics. Sleek and menacing crimson luxury: heavy punchy kick and crisp snare, swung hi-hats, gritty vinyl crackle, deep gliding 808 bass. Silky koto plucks and a slow minor-key shamisen hook, occasional taiko accents, a shakuhachi breath. Over it ominous gothic synth pads, velvet string swells and a cold harpsichord counter-line, vampire nightclub opulence. Steady loop-friendly groove from the first bar to the last, no intro build, no fade-out ending.
2. **boss_abomination:** Original brutal dark half-time trap hip-hop instrumental, 85 BPM feel, no vocals, no lyrics. Huge and monstrous: massive distorted 808 sub bass, crushing kick and slammed snare, thunderous taiko war drums and low toms, gritty vinyl texture and tape saturation. Detuned shamisen stabs, metallic anvil hits, a growling bowed-bass drone, ominous gothic organ and horror string clusters, low brass blasts. Relentless and heavy, combat-ready, steady loopable groove start to finish, no intro build, no fade-out ending.
3. **boss_knight:** Original dark cinematic boom-bap hip-hop instrumental, 94 BPM, no vocals, no lyrics. A swordsman's duel: sharp fast shamisen riffs as the lead hook, ringing steel blade-scrape textures and metallic percussion, hard kick and cracking snare, tight hi-hats, dusty vinyl crackle, deep 808 bass. Taiko hits on the turnarounds, a brief koto flourish, dark gothic strings and a cold synth pad underneath, vampire knight menace. Driving and precise, steady loopable groove start to finish, no intro build, no fade-out ending.
4. **boss_hollow:** Original feral dark trap hip-hop instrumental, half-time feel at 88 BPM, no vocals, no lyrics. A werewolf pack leader in a moonlit swamp: pounding tribal taiko ensemble and rolling toms, booming kick, snapping snare, deep growling 808 bass, gritty vinyl noise. Eerie howling wind and wolf-like synth glides, breathy wild shakuhachi cries, plucked shamisen pattern, ominous gothic drones and tense low strings. Primal and savage, combat-ready, steady loopable groove start to finish, no intro build, no fade-out ending.
5. **boss_shared:** Original dark cinematic boom-bap hip-hop instrumental, 92 BPM, no vocals, no lyrics. A battle theme for a lone sun-blooded swordsman hunting monsters in a rainy gothic port city: heavy kick and snare, crisp hi-hats, gritty vinyl crackle, deep 808 bass. A dark minor shamisen and koto hook, taiko hits, a shakuhachi phrase, ominous gothic synth pads and tense string ostinato. Urgent and driving, combat-ready, steady loopable groove start to finish, no intro build, no fade-out ending.
6. **rival_crowe:** Original cold, restrained dark hip-hop instrumental, 86 BPM boom-bap, no vocals, no lyrics. A mirror-match duel in a flooded crypt: a lone mournful shakuhachi melody with lots of space over a hard dry kick and snare, sparse hi-hats, dusty vinyl crackle, deep sustained 808 bass. Faint koto harmonics, a single distant taiko hit, cold glassy gothic synth pad, dripping-water reverb, a quiet low cello drone. Tense, minimal and icy, steady loopable groove start to finish, no intro build, no fade-out ending.

## Where each plays (`game/scripts/audio/audio.gd`)
| Fight | Hook | Music context |
|---|---|---|
| Marcus Crane (night boss `marcus`) | `hunt_director._spawn_boss` -> `Audio.set_boss(true, id)` | `boss_marcus` |
| Seraphine's Abomination (final boss `abomination`) | same | `boss_abomination` |
| Cassius Vane, the Blood Knight (night boss `knight`) | same | `boss_knight` |
| The Hollow Alpha (night boss `alpha`) | same | `boss_hollow` |
| Field bosses (Landmark guardians: Sir Aurelien, Dame Corvina, Old Gristle) and any boss without a theme | `boss_base.wake()` -> `Audio.engage(self, "boss")` | `boss` = `boss_shared` |
| Silas Crowe, the Pale Daywalker (Undercroft Depths) | `undercroft_rival._taunt()` -> `Audio.engage(self, "rival_crowe")` | `rival_crowe` |

All crossfade in over 1.2 s when the fight starts. On the boss's death (`set_boss(false)`), the
field boss's or rival's death, the rival's reset (Sol leaves), Sol moving 40 m away from a field
boss, or Sol falling, the music crossfades back to combat (enemies near) or explore. Both music
players are on the Music bus (`default_bus_layout.tres`), so the Music volume slider applies.

The old `combat.ogg` stays (it is the street-combat track); the round-3 boss themes were replaced in
place (same file names).
