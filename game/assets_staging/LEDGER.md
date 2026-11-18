# Higgsfield credit ledger, asset round 3 (2026-11-18)

Starting balance: 216.1 credits. Hard cap for this round: 195. Sub-caps: creatures 64, bosses 80, faces 14, world 27, audio 10.
Every paid 3D call was preflighted with `get_cost`; image and audio calls with `estimate_*_cost`.
Failed jobs were refunded by the server (checked with `balance`) and are listed at 0.

| # | Section | Item | Model | Credits | Job id | Result |
|---|---|---|---|---|---|---|
| 1 | creatures | werewolf run (Male_Head_Down_Charge, 512) | 3d_rigging | 8 | da1f4d37-6de3-45e6-903f-80b8fd87553d | ok |
| 2 | creatures | werewolf heavy swipe (Heavy_Hammer_Swing, 128) | 3d_rigging | 8 | dc14379a-ef26-4b37-bac2-431f0e0c89bd | ok |
| 3 | creatures | werewolf pounce (Leap_and_Punch, 464) | 3d_rigging | 0 | ee7f9911-e76b-42b6-b794-d16cd3761b04 | FAILED (server "something went wrong"), refunded |
| 4 | creatures | werewolf pounce retry, same clip (first failure looked transient) | 3d_rigging | 0 | 5d141377-f15c-4ad7-8422-1d94f14a3c2d | FAILED again, refunded: clip 464 apparently cannot be applied, switched clip |
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
| 15 | bosses | Marcus mesh (detailed geo + tex, PBR, align_image, 50k) | tripo_h3_1_multiview_to_3d | 18 | 57fd8333-3c96-4cdb-8e10-6ca23801bcdc | ok |
| 16 | bosses | Marcus slash combo (Weapon_Combo_1, 202) | 3d_rigging | 8 | 738f768b-ae09-4ec1-83fb-9f76862b5622 | ok |
| 17 | bosses | Marcus dash/lunge (Lunge_Spin_Kick, 216) | 3d_rigging | 8 | e45a9717-5615-4733-a167-72d6f832b619 | ok |
| 18 | bosses | Marcus death (Shot_and_Slow_Fall_Backward, 185) | 3d_rigging | 8 | 3399b13a-b0da-492e-b7c8-e415a52eb8cb | ok |
| 19 | bosses | Abomination mesh (text prompt, 40k, PBR) | tripo_3d | 5 | 8cc4c636-1822-4698-8f14-bb47f2c3db7f | ok |
| 20 | bosses | Abomination slam (Charged_Ground_Slam, 127) | 3d_rigging | 8 | aa7edcc7-4f27-4d66-a4d5-8a1c3e71862c | ok |
| 21 | bosses | Abomination grab (Grip_and_Throw_Down, 389) | 3d_rigging | 8 | 45ba79c8-34e6-4051-a522-8eba9eee4006 | |
| 22 | bosses | Abomination roar (Show_Both_Arm_Muscles, 388) | 3d_rigging | 8 | aa095790-e20b-4495-b91d-a4fc80a53d1a | |
| 23 | world | texture wet_cobblestone | gpt_image_2_6 (low) | 0.25 | 5a675b24-0fe9-4f2b-a247-77a27b0f7479 | ok |
| 24 | world | texture cracked_asphalt | gpt_image_2_6 (low) | 0.25 | fbc787b8-8ec3-423f-8bb4-0c562d85ccb3 | ok |
| 25 | world | texture brick | gpt_image_2_6 (low) | 0.25 | 457b2b16-ddf1-462d-a5f3-7e6a27236ccd | ok |
| 26 | world | texture limestone | gpt_image_2_6 (low) | 0.25 | c4132bab-666e-4aaf-9117-5e992eaf56e0 | ok |
| 27 | world | texture stucco | gpt_image_2_6 (low) | 0.25 | e152e755-9e39-4ccc-9c7f-89f1a59be078 | ok |
| 28 | world | texture rusted_metal | gpt_image_2_6 (low) | 0.25 | c8b5f44f-2523-48d1-b095-d966205a1f48 | ok |
| 29 | world | texture mud | gpt_image_2_6 (low) | 0.25 | 97d1f655-4011-4450-8c3c-dfc32e9bad26 | ok |
| 30 | world | texture wood_planks (after a free 429) | gpt_image_2_6 (low) | 0.25 | 1ff654b2-c37b-4b95-be49-1eaad399599e | |
