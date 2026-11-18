# Quality Loop

The owner's bar: **compete with Elden Ring** in look, animation, action and gameplay. Every change to the game goes through this loop until the critic scores every category 10/10, or until a category hits a documented hard ceiling.

## The cycle
1. **Fix round:** fix agents work in parallel, each owning its own files. They may split work into sub-agents, and they report to the coordinator. The coordinator merges, runs the smoke test, pushes, and confirms the CI browser render check passed and the site deployed.
2. **Test pass (testing agent):** plays the deployed build like a player, on desktop and on Pixel 7 emulation. It covers the menu, hub, drop-in, camps, combat (every move), dodging and parrying, loot, rank-ups, the Curfew, all 3 bosses, results, the inventory, the map, settings and touch controls. Output: `docs/qa/QA_ROUND_<n>.md`, listing functional bugs, feel problems, crashes and console errors, each with steps, evidence and severity.
3. **Critic pass (critic agent):** scores 10 categories /10 against the Elden Ring bar:
   1. Visuals
   2. Characters and animation
   3. Combat and feel
   4. Loop and level design
   5. Audio
   6. UI/UX
   7. Story and presentation
   8. Code
   9. Web and performance
   10. Overall

   Every lost point maps to a concrete fix (files, effort, credits). Output: `docs/CRITIC_REPORT_R<n>.md`, with a score table, issues, parallel fix groups and a ceiling section.
4. **Next fix round:** built from the QA and critic reports. Repeat.

## Rules for every agent
- **Starting point:** start from the latest `origin/claude/day-walker-game-concept-mz8vvv`. Commit WIP after each milestone, because usage limits can stop agents at any time. Never push; the coordinator merges and pushes.
- **Web safety:** keep `rendering/limits/spatial_indexer/threaded_cull_minimum_instances.web=65536` in `project.godot`. Without it the browser draws only sky above about 1000 instances; this is a Godot 4.3 single-threaded web bug. The CI render check guards it.
- **Textures:** character, prop and terrain textures import as Lossy (WebP), never VRAM-compressed. Phones can't decode S3TC, and CI fails on it.
- **Tests:** keep `game/tests/smoke_test.gd` passing. Add checks for what you build.
- **Evidence:** verify visually with screenshots (native under xvfb plus the web build in Playwright) and look at them.
- **Credits:** Higgsfield credits are scarce. Preflight the cost, stay inside your stated cap, and don't retry without reporting.

## Score history
| Round | Visuals | Chars/Anim | Combat | Loop | Audio | UI | Story | Code | Web | Overall |
|---|---|---|---|---|---|---|---|---|---|---|
| R0 (prototype) | 3 | – | 4 | – | 0 | – | 7 | 5 | 6 | 4 |
| R1 | 5 | 5 | 5 | 6 | 6 | 4 | 5 | 6 | 3 | 5 |
