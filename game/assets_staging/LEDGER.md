# Higgsfield credit ledger, asset round 3 (2026-11-18/19)

Starting balance: 216.1 credits. Hard cap for this round: 195. Sub-caps: creatures 64, bosses 80, faces 14, world 27, audio 10.
Every paid 3D call was preflighted with `get_cost`; image and audio calls with `estimate_*_cost`.
Failed, filtered and rate-limited (429) submissions were not charged (checked with `balance`) and are listed at 0.

## Totals

| Section | Sub-cap | Spent |
|---|---|---|
| Creatures | 64 | 64 |
| Bosses | 80 | 73 |
| Faces | 14 | 13.75 |
| World | 27 | 25 |
| Audio | 10 | 9.9 |
| **Total** | **195** | **185.65** |

Closing balance: 30.45 credits (216.1 - 185.65), confirmed with `balance`.

## Items

| # | Section | Item | Model | Credits | Job id | Result |
|---|---|---|---|---|---|---|
| 1 | creatures | werewolf run (Male_Head_Down_Charge, 512) | 3d_rigging | 8 | da1f4d37-6de3-45e6-903f-80b8fd87553d | ok |
| 2 | creatures | werewolf heavy swipe (Heavy_Hammer_Swing, 128) | 3d_rigging | 8 | dc14379a-ef26-4b37-bac2-431f0e0c89bd | ok |
| 3 | creatures | werewolf pounce (Leap_and_Punch, 464) | 3d_rigging | 0 | ee7f9911-e76b-42b6-b794-d16cd3761b04 | FAILED (server "something went wrong"), refunded |
| 4 | creatures | werewolf pounce retry, same clip (the first failure looked transient) | 3d_rigging | 0 | 5d141377-f15c-4ad7-8422-1d94f14a3c2d | FAILED again, refunded; clip 464 seems not to apply, so the clip was switched |
| 5 | creatures | werewolf pounce (Jumping_Punch, 457) | 3d_rigging | 8 | aa802bce-2250-4854-b5b3-4e27dd495192 | ok |
| 6 | creatures | werewolf roar (Zombie_Scream, 386) | 3d_rigging | 8 | ebe32310-238b-4c38-982f-150d8f54f98d | ok |
| 7 | creatures | werewolf death (Knock_Down_1, 190) | 3d_rigging | 8 | a943ce2e-c0f9-401f-b61f-9585be2507fa | ok |
| 8 | creatures | vampire lunge (Thrust_Slash, 240) | 3d_rigging | 8 | 71931daf-1910-48f2-9b11-608871cd613e | ok |
| 9 | creatures | vampire claw combo (Weapon_Combo, 199) | 3d_rigging | 8 | 94a4a6e7-d6a8-442f-b3b5-17a3de263e92 | ok |
| 10 | creatures | vampire backflip (Backflip, 452) | 3d_rigging | 8 | e4adaee4-8781-4293-9a50-9cba7d464d70 | ok |
| 11 | bosses | Marcus front view | gpt_image_2_6 (medium) | 0.5 | f73917fe-140a-4a76-902e-b3d459f29378 | ok |
| 12 | bosses | Marcus left view (front as reference) | gpt_image_2_6 (medium) | 0.5 | 3a5d05ec-369c-4bf1-af01-33b426bca3d6 | ok |
| 13 | bosses | Marcus back view | gpt_image_2_6 (medium) | 0.5 | 85b0cb56-214b-4560-8724-64f6a4e63a84 | ok |
| 14 | bosses | Marcus right view | gpt_image_2_6 (medium) | 0.5 | 60d3a3df-12ca-4883-9447-686307147b45 | ok |
| 15 | bosses | Marcus mesh (detailed geometry and texture, PBR, align_image, 50k) | tripo_h3_1_multiview_to_3d | 18 | 57fd8333-3c96-4cdb-8e10-6ca23801bcdc | ok |
| 16 | bosses | Marcus slash combo (Weapon_Combo_1, 202) | 3d_rigging | 8 | 738f768b-ae09-4ec1-83fb-9f76862b5622 | ok |
| 17 | bosses | Marcus dash/lunge (Lunge_Spin_Kick, 216) | 3d_rigging | 8 | e45a9717-5615-4733-a167-72d6f832b619 | ok |
| 18 | bosses | Marcus death (Shot_and_Slow_Fall_Backward, 185) | 3d_rigging | 8 | 3399b13a-b0da-492e-b7c8-e415a52eb8cb | ok |
| 19 | bosses | Abomination mesh (text prompt, 40k, PBR) | tripo_3d | 5 | 8cc4c636-1822-4698-8f14-bb47f2c3db7f | ok |
| 20 | bosses | Abomination slam (Charged_Ground_Slam, 127); rigged alone first to check the hybrid mesh rigs | 3d_rigging | 8 | aa7edcc7-4f27-4d66-a4d5-8a1c3e71862c | ok |
| 21 | bosses | Abomination grab/throw (Grip_and_Throw_Down, 389) | 3d_rigging | 8 | 45ba79c8-34e6-4051-a522-8eba9eee4006 | ok |
| 22 | bosses | Abomination roar (Show_Both_Arm_Muscles, 388) | 3d_rigging | 8 | aa095790-e20b-4495-b91d-a4fc80a53d1a | ok |
| 23 | faces | Nia front capture, first prompt ("bare shoulders") | gpt_image_2_6 (medium) | 0 | 1c6e003a-879f-4b2d-a4a7-209167b11bcc | flagged by the content filter, not charged |
| 24 | faces | Nia front capture (t-shirt) | gpt_image_2_6 (medium) | 0.5 | 08db912c-c67b-457d-b723-8e354e4650e8 | ok |
| 25 | faces | Nia left 30 | gpt_image_2_6 (low) | 0.25 | 52c37e74-9594-48e1-a583-154f12c79981 | ok |
| 26 | faces | Nia right 30 | gpt_image_2_6 (low) | 0.25 | 2fc311e7-2bb4-4f5f-855c-932628178417 | ok |
| 27 | faces | Nia left 90 | gpt_image_2_6 (low) | 0.25 | 8896bf31-3ae7-4cc4-a854-7247ad48189c | ok |
| 28 | faces | Nia right 90 | gpt_image_2_6 (low) | 0.25 | f1f22572-b831-4b72-ad1b-49e219be75a9 | ok |
| 29 | faces | Nia back | gpt_image_2_6 (low) | 0.25 | 77d256cc-0e3a-484b-a0a3-670fccce43e1 | ok |
| 30 | faces | Nia head reconstruction (geometry only, detailed, 200k) | tripo_h3_1_multiview_to_3d | 12 | 8f45a906-67ac-43ac-925a-067b0c614c13 | ok |
| 31 | world | texture wet_cobblestone | gpt_image_2_6 (low) | 0.25 | 5a675b24-0fe9-4f2b-a247-77a27b0f7479 | ok |
| 32 | world | texture cracked_asphalt | gpt_image_2_6 (low) | 0.25 | fbc787b8-8ec3-423f-8bb4-0c562d85ccb3 | ok |
| 33 | world | texture brick | gpt_image_2_6 (low) | 0.25 | 457b2b16-ddf1-462d-a5f3-7e6a27236ccd | ok |
| 34 | world | texture limestone | gpt_image_2_6 (low) | 0.25 | c4132bab-666e-4aaf-9117-5e992eaf56e0 | ok |
| 35 | world | texture stucco | gpt_image_2_6 (low) | 0.25 | e152e755-9e39-4ccc-9c7f-89f1a59be078 | ok |
| 36 | world | texture rusted_metal | gpt_image_2_6 (low) | 0.25 | c8b5f44f-2523-48d1-b095-d966205a1f48 | ok |
| 37 | world | texture mud | gpt_image_2_6 (low) | 0.25 | 97d1f655-4011-4450-8c3c-dfc32e9bad26 | ok |
| 38 | world | texture wood_planks (resubmitted after a free 429) | gpt_image_2_6 (low) | 0.25 | 1ff654b2-c37b-4b95-be49-1eaad399599e | ok |
| 39 | world | texture forest_floor (resubmitted after a free 429) | gpt_image_2_6 (low) | 0.25 | 4b13dc9e-e528-44cf-a017-f626d25aef55 | ok |
| 40 | world | texture mossy_rock | gpt_image_2_6 (low) | 0.25 | 98362252-5aab-467c-9b15-6a127b2c95b6 | ok |
| 41 | world | texture cliff_rock | gpt_image_2_6 (low) | 0.25 | 6337718e-651e-4047-b03a-a70aa3d33f78 | ok |
| 42 | world | texture bark_pine | gpt_image_2_6 (low) | 0.25 | 549e4aa0-50c9-4dc9-a13c-83dfb5630ff4 | ok |
| 43 | world | texture bark_cypress | gpt_image_2_6 (low) | 0.25 | c435db9b-42ba-4ee6-9772-2de60c8e75c6 | ok |
| 44 | world | texture cemetery_marble | gpt_image_2_6 (low) | 0.25 | 5197c792-e30f-4b36-be78-72fd74431bbf | ok |
| 45 | world | texture wet_sand | gpt_image_2_6 (low) | 0.25 | 221f987e-602e-4d43-8305-b49737045036 | ok |
| 46 | world | card pine_branch_card | gpt_image_2_6 (low) | 0.25 | a8b65ba3-bdc2-4980-82d8-acc1f5feb267 | ok |
| 47 | world | card moss_card | gpt_image_2_6 (low) | 0.25 | 07feac0c-5c66-4466-b4ed-6915aa624785 | ok |
| 48 | world | texture weathered_concrete | gpt_image_2_6 (low) | 0.25 | 1b9948f1-7786-46e7-bf97-aea72f6a141b | ok |
| 49 | world | texture slate_roof (resubmitted after a free 429) | gpt_image_2_6 (low) | 0.25 | 3b5be7b0-72e3-4d2f-b396-a21fe09de2e9 | ok |
| 50 | world | texture tar_roof_gravel | gpt_image_2_6 (low) | 0.25 | b270a7a5-948a-4c28-b685-9e154a923d52 | ok |
| 51 | world | prop mausoleum (18k) | tripo_3d | 5 | cc3ca11f-9910-4b0d-a61f-e2677f945645 | ok |
| 52 | world | prop cast-iron gazebo (18k) | tripo_3d | 5 | 92b8c49e-17df-412c-9379-30504631c4b8 | ok |
| 53 | world | prop wrecked fishing boat (18k) | tripo_3d | 5 | 1d8c858f-bff7-4f43-a510-2328c88f9806 | ok |
| 54 | world | prop Victorian street clock (15k) | tripo_3d | 5 | 43d91717-f9e0-4cd2-9de5-248d9dd4c2c4 | ok |
| 55 | audio | Marcus boss theme, 50 s instrumental | elevenlabs_music_v2 | 3.2 | 642267bc-a803-421c-bb4e-c8e8cb6c63f4 | ok |
| 56 | audio | Abomination boss theme, 50 s | elevenlabs_music_v2 | 3.2 | b217adc4-e6ff-4b24-b7cc-df10baa65a97 | ok (last 5 s were a fade, cut for the loop) |
| 57 | audio | werewolf roar, 2 s | mirelo_text_to_audio | 0.5 | d7889d32-28bf-4b5b-9585-c1de0cb40fc0 | ok |
| 58 | audio | claw swipe, 2 s | mirelo_text_to_audio | 0.5 | 8dc71b0d-337f-485c-a1ec-b5d9cbded9af | ok (quiet; +16 dB) |
| 59 | audio | pounce whoosh, 2 s (resubmitted after a free 429) | mirelo_text_to_audio | 0.5 | 26de6c49-482e-4ddc-9bd1-afde6b918f78 | ok |
| 60 | audio | vampire hiss, 2 s | mirelo_text_to_audio | 0.5 | ed6d5cce-19b0-4105-8cb9-ea404ddd4ed4 | ok |
| 61 | audio | vampire lunge whoosh, 2 s | mirelo_text_to_audio | 0.5 | 136face8-72c0-4f63-a0a9-07f0b960f8f2 | ok |
| 62 | audio | boss slam impact, 2 s | mirelo_text_to_audio | 0.5 | f16f8f14-9422-4d2e-be60-44296da57664 | ok |
| 63 | audio | body fall, 2 s | mirelo_text_to_audio | 0.5 | 0afb7ae3-0f6e-468c-8d04-f8d242e01f4a | ok |

Result URLs follow `https://d8j0ntlcm91z4.cloudfront.net/user_3M3cbVYOpQkCAbZXwwBloXVahos/hf_<date>_<time>_<job id>.<ext>`; every result was downloaded into the round-3 scratchpad (`assets_r3/dl/`). The 5-12 MB full rig downloads stay there, out of git.

Uploaded rig sources (`media_upload` + PUT + `media_confirm`, type file, no charge): Marcus `832d19e8-d9e5-4a3f-80e1-bf74dc4b535a.glb`, Abomination `b146ef2d-4dec-4431-a42c-348de9b9effc.glb`; Nia's design reference re-uploaded as image `4cf5a2bc-47a9-43a9-a99a-867aea720419`.

Not done for budget: the Sol ±30 degree face re-capture (about 0.5-1 credit, see `faces/README.md`).
