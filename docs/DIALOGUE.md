# Daywalker: dialogue

All voiced lines live in `game/data/dialogue.json` (id, speaker, text, audio path, subtitle duration, priority, cooldown) and play through the `Dialogue` autoload (`game/scripts/audio/dialogue.gd`):

```gdscript
Dialogue.play("curfew_warning")     # one line by id
Dialogue.play_group("bark_dodge_")   # a random variant
Audio.set_boss(true)                 # boss music; set_boss(false) when it dies
```

Rules: one voice channel, so lines never overlap (and a speaker never talks over themself). Priority 3 (boss) cuts in over anything lower; comms (2) queue for up to 20 s; barks and taunts (1) drop if the channel is busy with another bark, or wait at most 1.5 s. Every line has a cooldown in the JSON. Subtitles show the speaker's name in their colour and can be switched off in Options. Audio files: `game/assets/audio/voice/<id>.ogg`.

## Voices

| Speaker | Direction |
|---|---|
| Sol | low, calm, dry wit, a Southern edge |
| Nia | smart, warm and wry, always on comms |
| Count Lucien | charming, theatrical, old-world (working name; the critic report suggests a rename) |
| Marcus Crane | Velvet Court duelist, smooth and vain |
| Seraphine | elegant, intimate, terrifying |
| Detective Reyes | clipped, tired, police radio |
| Vampire / Velvet Court | a feral street vampire / a courtier with manners |

## Hooks for the Hunt branch

| Event | Call |
|---|---|
| Hub reached | `Dialogue.play("hunt_hub")` |
| Deploy | `Dialogue.play_group("hunt_deploy_")` |
| Point of interest spotted | `Dialogue.play("hunt_poi_found")` |
| Point of interest cleared | `Dialogue.play_group("poi_cleared_")` |
| Red Curfew ring starts closing | `Dialogue.play("curfew_broadcast")`, then `Dialogue.play("curfew_warning")` (they queue) |
| Ring almost shut | `Dialogue.play("curfew_final")`; optional `Dialogue.play("reyes_scanner")` |
| Run complete / extraction | `Dialogue.play("hunt_extract")` |
| Hollow Alpha appears | `Audio.play_at("wolf_howl", pos)`, `Audio.set_boss(true)`, `Dialogue.play("boss_alpha_intro")` |
| Hollow Alpha dies | `Audio.set_boss(false)`, `Dialogue.play("boss_alpha_death")` |
| Marcus Crane appears / dies | `Dialogue.play("boss_marcus_intro")` / `Dialogue.play("boss_marcus_death")` (+ `Audio.set_boss`) |
| Seraphine's Abomination appears / dies | `Dialogue.play("boss_seraphine_intro")` / `Dialogue.play("boss_seraphine_death")` (+ `Audio.set_boss`) |

## Main menu: the lair

Nia and Sol, while the menu idles. One exchange (a then b) roughly every 22-36 s after 9 s without input; any click stops it. Played by `Dialogue.start_menu_banter()` from `main_menu.gd`.

| id | speaker | line | hooked in |
|---|---|---|---|
| `menu_lair_01a` | Nia | You've sharpened that thing three times. |  |
| `menu_lair_01b` | Sol | Fourth time's for luck. |  |
| `menu_lair_02a` | Nia | Your blood sample just ate my control sample. |  |
| `menu_lair_02b` | Sol | Sounds about right. Did it say thank you? |  |
| `menu_lair_03a` | Nia | Reyes left another voicemail. She sounds... thorough. |  |
| `menu_lair_03b` | Sol | She's a good cop. That's the problem. |  |
| `menu_lair_04a` | Nia | You could sleep, you know. Like a normal person. |  |
| `menu_lair_04b` | Sol | Tried it once. Didn't take. |  |
| `menu_lair_05a` | Nia | The Court's throwing a party on the Velvet Mile tonight. |  |
| `menu_lair_05b` | Sol | Then I reckon I'm crashing it. |  |
| `menu_lair_06a` | Nia | Hunger's at forty percent. I'm writing that down. |  |
| `menu_lair_06b` | Sol | Write it in pencil, Doc. |  |
| `menu_lair_07a` | Nia | Rain's coming down hard up top. |  |
| `menu_lair_07b` | Sol | Good. Hides the smell. Theirs and mine. |  |
| `menu_lair_08a` | Nia | If you die out there, I'm keeping the coat. |  |
| `menu_lair_08b` | Sol | It wouldn't fit you. Barely fits me. |  |

## Start, hub and deploy (Nia over comms)

`hunt_start` plays when a game starts. The rest are for the Hunt run structure (hub, deploy, points of interest), whose hooks are added when that branch merges.

| id | speaker | line | hooked in |
|---|---|---|---|
| `hunt_start` | Nia | Comms are up. I can hear you breathing, so that's a good start. | main.gd `start_game()` |
| `hunt_hub` | Nia | Pick your steel, pick your ground. Every district's crawling tonight. |  |
| `hunt_deploy_1` | Nia | Dropping you in. Three marks on the map. Hit them before the Curfew closes. |  |
| `hunt_deploy_2` | Nia | Out of the tunnels and into the rain. Try to bring the coat back dry. |  |
| `hunt_poi_found` | Nia | That signal's a nest. Clear it, and whatever they're guarding is yours. |  |

## Sol's barks

Variants share a cooldown; `Dialogue.play_group("bark_bite_")` picks one.

| id | speaker | line | hooked in |
|---|---|---|---|
| `bark_bite_1` | Sol | Mm. Vintage. | player.gd `_bite()` |
| `bark_bite_2` | Sol | That'll hold me. | player.gd `_bite()` |
| `bark_dodge_1` | Sol | Too slow. | main.gd `perfect_dodge()` |
| `bark_dodge_2` | Sol | Missed me, darlin'. | main.gd `perfect_dodge()` |
| `bark_lowhp_1` | Sol | Okay. That one hurt. | player.gd `take_damage()` below 30% blood |
| `bark_lowhp_2` | Sol | Need blood. Now. | player.gd `take_damage()` below 30% blood |
| `bark_frenzy` | Sol | Can't... hold it... back! | player.gd `add_hunger()` frenzy start |
| `bark_levelup_1` | Sol | Feel that? Stronger. | progression.gd `level_up()` |
| `bark_levelup_2` | Sol | Gettin' the hang of this. | progression.gd `level_up()` |
| `bark_eclipse` | Sol | Eclipse steel. Somebody's gonna miss this. | loot.gd `pick_up()` of an Eclipse item |
| `bark_sunrise` | Sol | Sun's up. Run, little bats. | main.gd sunrise |
| `bark_nightfall` | Sol | Here comes the night shift. | main.gd nightfall |
| `bark_kill_1` | Sol | Stay down. | enemy.gd `_die()` (22%) |
| `bark_kill_2` | Sol | Who's next? | enemy.gd `_die()` (22%) |

## Comms during play

Nia, plus Lucien's curfew broadcast and Detective Reyes on the police scanner.

| id | speaker | line | hooked in |
|---|---|---|---|
| `curfew_warning` | Nia | Red Curfew's closing. Get inside the ring, Sol, or it gets inside you. |  |
| `curfew_final` | Nia | Ring's almost shut. Move. Now. |  |
| `poi_cleared_1` | Nia | Nest's clear. Nice work. Grab what's shiny and go. |  |
| `poi_cleared_2` | Nia | That's one less hole full of teeth. |  |
| `nia_low_blood` | Nia | Your blood's crashing. Find a neck. Well, not any neck. | player.gd `take_damage()` below 20% blood |
| `nia_full_moon` | Nia | Full moon's up. The Pack is out in force. Don't let them flank you. | main.gd full-moon nightfall |
| `nia_sunrise` | Nia | Sun's coming. The bloodsuckers scramble. You don't. | main.gd sunrise (or Sol's bark) |
| `hunt_extract` | Nia | Hunt's done. Get to extraction and I'll put the kettle on. |  |
| `curfew_broadcast` | Lucien | Citizens of Port Vesper. The Red Curfew is in effect. Stay indoors... and stay delicious. |  |
| `reyes_scanner` | Det. Reyes | All units, Curfew zone is sealed. Man in the long coat, do not engage. I mean it. |  |

## Enemy taunts

Played now and then when an enemy winds up a strike (`Audio.enemy_bark`). Wolves growl and howl with sound effects, not voice.

| id | speaker | line | hooked in |
|---|---|---|---|
| `vamp_taunt_1` | Vampire | Half-breed! You smell like a church. | enemy.gd wind-up |
| `vamp_taunt_2` | Vampire | The Count wants you alive. Mostly. | enemy.gd wind-up |
| `vamp_taunt_3` | Vampire | Come here, Daywalker. Let me taste you. | enemy.gd wind-up |
| `court_taunt_1` | Velvet Court | The Velvet Court sends its regards. | enemy.gd wind-up |
| `court_taunt_2` | Velvet Court | You're terribly underdressed for this party. | enemy.gd wind-up |
| `court_taunt_3` | Velvet Court | Kneel, and Lucien might let you keep your head. | enemy.gd wind-up |

## Bosses

The Hollow Alpha gets the growl and howl SFX plus Nia's lines.

| id | speaker | line | hooked in |
|---|---|---|---|
| `boss_alpha_intro` | Nia | That howl is the Alpha. She's big, she's angry, and she brought family. |  |
| `boss_alpha_death` | Nia | Alpha's down. The Pack won't forget that. |  |
| `boss_marcus_intro` | Marcus Crane | Look at us. Two fast men in nice coats. Only one walks out tonight. |  |
| `boss_marcus_death` | Marcus Crane | Faster... than me? Nobody's... faster... |  |
| `boss_seraphine_intro` | Seraphine | My darling abomination. Show the Daywalker what his blood has made. |  |
| `boss_seraphine_death` | Seraphine | You killed my child. I'll make another... from you. |  |

Total: 57 lines.
