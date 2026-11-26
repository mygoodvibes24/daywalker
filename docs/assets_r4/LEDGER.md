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

---

# Asset round 4 ledger: Sol's voice (deeper, more aggressive)

Owner's request: Sol's voice should have "more of an aggressive tone". The owner pointed to a real
actor's performance as a vampire hunter as the reference. That voice was **not** cloned, imitated or
named anywhere. No reference audio was uploaded and no custom voice was created. Instead, an existing
Higgsfield preset voice was picked to match a written brief:

> a deep, low, gravelly adult male baritone; controlled menace; terse, clipped delivery; cold confidence
> that snaps into aggressive barks in combat; a slight rasp; no theatrical villain cackle, not cartoonish.

**Voice:** Higgsfield preset **Gideon** (`1ad38ba4-9cc4-4f2f-9fde-b0fefdf67ae5`) on `elevenlabs_v4` (Eleven v4,
the model the rest of the cast uses), default stability and similarity. It replaces the preset Brooks.

**How it was picked:** none of the presets has a written description, and there is no audio output here.
So the preview clips of all 40 male presets were downloaded and measured: median pitch (F0) and
harmonics-to-noise ratio (HNR; lower means rougher, more gravel). Gideon was the deepest (82 Hz median F0,
against 104 Hz for Brooks) and the roughest (HNR -0.2 dB, against 2.7 dB for Brooks). The next candidates
were Landon (95 Hz) and Sterling (101 Hz).

**Direction:** each line carries an Eleven v4 audio tag before the text, which shapes the delivery and is
not spoken. Story lines (the lair banter) use `[low, dry ...]`, `[low, grim]` or `[low, cold, quiet menace]`.
Combat barks use `[harsh, aggressive]`, `[cold, contemptuous]` or `[snarling, furious, losing control]`.
The spoken text is exactly the subtitle text, and every take was checked with speech recognition
(faster-whisper `base.en`). All 22 transcripts match the subtitles, and no tag was read aloud. Measured on the
results, the calm lines sit at about 80-90 Hz (the old Sol: about 125 Hz). The barks rise to 150-210 Hz
because they are shouted.

**Credits:** 7.38 in all (cap: 15), confirmed against `transactions`. Balance 142.62 before. Other agents ran
3D Rigging jobs (8 x 8 credits) at the same time, so the balance afterwards (71.24) also reflects their spend.
- Tests: 0.71 (four jobs, below).
- Full set: 6.67 (22 jobs, 15 at 0.23 and 7 at 0.46; Eleven v4 bills 0.46 for a tagged line over about 50 characters).

No job failed. Many submissions were refused by the rate limit (at most 2 concurrent jobs). Those refusals
cost nothing and created no job, and each refused line was submitted again once earlier jobs finished.
Every line was generated exactly once. Nothing was retried for quality.

## Test lines
| # | Line | Model | Voice | Credits | Job id | Verdict |
|---|---|---|---|---|---|---|
| T1 | `[growls, aggressive] Stay down.` | elevenlabs_v4 | Gideon | 0.23 | a2ee6c55-c18b-4128-9d66-75c1c87e63f5 | The `growls` tag added about 0.6 s of actual growling before the line, so it was not used for the full set |
| T2 | `[low, cold, menacing] Sun's coming. You're not.` | elevenlabs_v4 | Gideon | 0.23 | e0b939b0-9450-4019-aa79-a396f06e83d0 | Chosen: very low (55-110 Hz), rough, no tag read aloud |
| T3 | `[growls, aggressive] Stay down.` | elevenlabs_v4 | Landon | 0.23 | 734ff7c5-14cb-4b92-ad94-ad4a2b061a5e | Rejected: shouted at 250-300 Hz, with an "Ugh" added |
| T4 | Sun's coming. You're not. (instruction: deep gravelly baritone ...) | qwen_audio_tts | Gideon id | 0.02 | 15a7e822-314b-4a7d-a5d9-216ad86b60f4 | Deep (about 72 Hz) but clipped (0 dBFS) and not the cast's model; not used |

## Shipped set (`elevenlabs_v4`, preset Gideon)
| # | File (`game/assets/audio/voice/`) | Line (subtitle, unchanged) | Tag | Credits | Job id | Length |
|---|---|---|---|---|---|---|
| 1 | `menu_lair_01b` | Fourth time's for luck. | `[low, dry, unhurried]` | 0.23 | c1c7d6ae-7b7c-4cb4-8a12-6fddd96e280f | 1.80 s |
| 2 | `menu_lair_02b` | Sounds about right. Did it say thank you? | `[low, dry, deadpan]` | 0.46 | 36ea811b-11ad-4290-aa7e-f09c8c431dc7 | 3.49 s |
| 3 | `menu_lair_03b` | She's a good cop. That's the problem. | `[low, grim]` | 0.23 | 6787e7da-16cc-4ea0-847a-62c3fcf1ad8b | 2.85 s |
| 4 | `menu_lair_04b` | Tried it once. Didn't take. | `[low, flat, dry]` | 0.23 | aca1baa2-08f6-4ec6-8ee2-20653508c901 | 2.40 s |
| 5 | `menu_lair_05b` | Then I reckon I'm crashing it. | `[low, cold, quiet menace]` | 0.46 | 386c7cf1-e450-40f7-b88b-1a4657523681 | 2.04 s |
| 6 | `menu_lair_06b` | Write it in pencil, Doc. | `[low, dry]` | 0.23 | 05a26d27-896f-4c41-bee3-760bd87f5e39 | 1.92 s |
| 7 | `menu_lair_07b` | Good. Hides the smell. Theirs and mine. | `[low, grim, quiet]` | 0.46 | e85555ea-4e4c-42dc-a02d-e3b645b9db6a | 3.93 s |
| 8 | `menu_lair_08b` | It wouldn't fit you. Barely fits me. | `[low, dry, deadpan]` | 0.46 | 173da6cd-0139-4358-82cf-dc786a6a483f | 2.95 s |
| 9 | `bark_bite_1` | Mm. Vintage. | `[low, cold, satisfied]` | 0.23 | 0a3bf91c-db39-4b4e-b263-3af42ce67e20 | 2.17 s |
| 10 | `bark_bite_2` | That'll hold me. | `[low rasp, cold]` | 0.23 | 85b6face-42f9-45eb-a693-5f2229317c9a | 1.42 s |
| 11 | `bark_dodge_1` | Too slow. | `[cold, contemptuous]` | 0.23 | 7a9356b9-5d3b-4c8f-ad3d-1fea369e11ab | 1.27 s |
| 12 | `bark_dodge_2` | Missed me, darlin'. | `[cold, mocking]` | 0.23 | 1378454e-152f-41e4-8f70-f2dcc1e1d982 | 1.60 s |
| 13 | `bark_lowhp_1` | Okay. That one hurt. | `[strained, through gritted teeth]` | 0.46 | 2b1c2bdc-8284-440c-83af-a641687f49a3 | 2.73 s |
| 14 | `bark_lowhp_2` | Need blood. Now. | `[strained, harsh, urgent]` | 0.23 | 5a76552e-d5b1-4e49-9cee-8c03142b4a40 | 2.19 s |
| 15 | `bark_frenzy` | Can't... hold it... back! | `[snarling, furious, losing control]` | 0.46 | 4476f9dd-730d-424f-a5fb-9ad0680d0976 | 2.50 s |
| 16 | `bark_levelup_1` | Feel that? Stronger. | `[low, menacing]` | 0.23 | 83f244b2-c759-40fb-bb6a-adb66c9c36a6 | 2.32 s |
| 17 | `bark_levelup_2` | Gettin' the hang of this. | `[low, cold confidence]` | 0.23 | 8defa935-a91d-4bfb-bc25-bda4ec502981 | 1.50 s |
| 18 | `bark_eclipse` | Eclipse steel. Somebody's gonna miss this. | `[low, cold, controlled]` | 0.46 | 03a9d8cc-238b-4cb1-b724-9fd0086e9ec8 | 3.55 s |
| 19 | `bark_sunrise` | Sun's up. Run, little bats. | `[harsh, aggressive]` | 0.23 | 6acae296-5304-4111-b2d1-0a8105c84f9b | 2.27 s |
| 20 | `bark_nightfall` | Here comes the night shift. | `[low, menacing]` | 0.23 | 6c6aa45a-8d42-4c21-9adf-092b936b54e8 | 1.98 s |
| 21 | `bark_kill_1` | Stay down. | `[harsh, aggressive bark]` | 0.23 | 2a14d974-3ab7-4d58-891d-8520c412722a | 1.38 s |
| 22 | `bark_kill_2` | Who's next? | `[harsh, aggressive]` | 0.23 | 12921e0f-5032-4d31-812d-447d697e286a | 1.06 s |

`boss_knight_death` and `rival_death` reuse `bark_kill_1.ogg`, so all 24 Sol entries in `dialogue.json` now
play the new voice. No file name, key or subtitle changed. The `duration` fields were left as they were:
`dialogue.gd` holds a line for the longer of `duration` and the stream length. Result URLs:
`https://d8j0ntlcm91z4.cloudfront.net/user_3M3cbVYOpQkCAbZXwwBloXVahos/hf_20261126_<time>_<job id>.mp3`.

## Processing
1. Start from the MP3 output and convert to mono 22.05 kHz.
2. Trim silence below -45 dBFS, keeping a 60 ms lead-in and a 150 ms tail.
3. Normalise: the lair lines to about -16.5 LUFS, matching Nia's lines (-16.7 to -16.8), and the combat barks to about -15.5 LUFS, matching the old barks (-15.6). Use an iterative gain under a limiter at -3.6 dBFS. After encoding, most peaks sit at -1 to -3.5 dBFS. Two barks, `bark_levelup_1` and `bark_nightfall`, overshoot to about 0 dBFS on decode.
4. Encode as OGG Vorbis q2, mono 22.05 kHz, the same format as the rest of the voice set.

Nobody has listened to the takes yet, because there is no audio output here. Before calling them final,
check that the barks are aggressive without sounding cartoonish. If a single line misses, one take costs
0.23-0.46 credits.

`game/tests/smoke_test.gd` now checks that every Sol line loads an Ogg Vorbis stream between 0.5 and 6 s
long (24 lines).
