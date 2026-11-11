# LAST STATION

A short first-person repair puzzler for Godot 4 (GDScript only). The station is failing: you have 6 minutes of oxygen reserve (on the standard level; see Levels) to repair **Power**, **Oxygen**, **Comms** and **Cooling**, then reboot the station. An offline help assistant, **ORACLE**, answers questions from the station manuals.

Built as a two-day-scope prototype. Specification: `AGENTS.md` and `REQUIREMENTS.md`. Test evidence: `docs/TEST_REPORT.md`.

## Run

1. Install Godot 4 (Standard edition). Developed and tested with **4.7.2.stable** on macOS.
2. Open Godot, **Import** `project.godot`, press **F5**.
3. Windows build and export steps: `docs/WINDOWS_SETUP.md` (not verified on Windows; no `.exe` has been built).

## Purpose

The Last Station has lost power, the crew are asleep in hibernation and the oxygen is running out. ORACLE, the station's old help system, remembers how every system works. You repair Power, Oxygen, Comms and Cooling before the reserve reaches zero.

As a project it is a demonstration of a **RAG assistant inside a game**: the rules live in written manuals, ORACLE finds the right manual by keyword and answers from it, and the game is built so the AI can never change the game.

## How to play

1. Press **Play**. You wake up in the crew quarters, facing the door and the **PROTOCOL** sign beside it. The oxygen reserve (6:00 on shift 1 on Engineer) starts when you first move. **Shift 1 is a guided shift:** it always uses Protocol A and a line at the bottom tells you what to do next.
2. The top-left checklist shows what is left and the current **PROTOCOL (A or B)**. Walk the corridor east to the four rooms and repair each system, then walk all the way back west and press **E** on the reboot terminal.
3. Aim the `+` at a terminal until `E — ...` appears, then press **E**.
4. **The game does not tell you the rules.** Read the panels in each room, then press **M** (manuals) or **H** (ORACLE) to look up what to do. The protocol changes the rules, so check it each shift.

**Score** = 300 + (reserve seconds left ÷ 2) − 50 per retry (retry penalty capped at 150). Maximum 480 on shift 1 on Engineer; the level multiplies it (see Levels). Your best shift score is saved.

**Runs get harder.** Press **Next Shift** after a win to keep going: every shift has 45 seconds less reserve (on Engineer: 360, 315, 270, 225, then 180 at the lowest), and your **run total** adds up the score of each shift you clear. Your best run is saved.

**Hints.** In ORACLE (press H) the **Get a hint** button costs 20 seconds of reserve. It tells you the next system to repair and which protocol rules apply, but never the answer. (Typing "hint" to ORACLE does not use one.)

<details><summary>Spoiler: the full rules (the same text is in the in-game manuals)</summary>

| Room | Protocol A | Protocol B |
|---|---|---|
| **POWER** (left): flip the 4 breakers by voltage | `RESTORE` lowest first, `SHED` highest first | reversed: `RESTORE` highest first, `SHED` lowest first |
| **OXYGEN** (middle): station mode, then valves A/B/C | NIGHT 30/40/50, DAY 50/60/70, EMERGENCY 70/80/90 | NIGHT 40/50/60, DAY 60/70/80, EMERGENCY 80/90/100 |
| **COMMS** (third): count the lit beacons | 100 + 20 × lit MHz | 100 + 10 × lit MHz |
| **COOLING** (fourth): read the CORE TEMP and the REACTOR state, set the coolant flow | (CORE TEMP − 400) ÷ 20 L/s | (CORE TEMP − 400) ÷ 10 L/s |

In the Cooling room, add 5 L/s to the flow when the REACTOR state is SURGE. The coolant panel repeats the CORE TEMP and REACTOR state, because it covers the wall display.

A wrong breaker costs 15 s; wrong valves, a wrong frequency or a wrong coolant flow cost 10 s.
</details>

## Controls

| Key | Action |
|---|---|
| W A S D / mouse | Move / look |
| E | Interact |
| M | Manuals (pauses the game) |
| H | ORACLE help chat (pauses the game) |
| V | Switch first / third person view |
| C | Swing the camera in front of the character to see its face (press again to go back) |
| B | Theme song on / off |
| N | All sound on / off |
| Esc | Pause, or close a panel |
| Hold R (1 s) | Retry this shift (same station, **new puzzle values**) |

## Levels

Pick **Rookie**, **Engineer** or **Survivor** on the main menu (your choice is saved). Engineer is the standard game; every other number in this README and in the manuals is Engineer's. A shift score is multiplied by the level, so a harder level is worth more, and the level is shown at the top of the objectives and on the win screen.

| | Rookie | Engineer | Survivor |
|---|---|---|---|
| Starting reserve (shift 1) | 480 s | 360 s | 270 s |
| Less each later shift, to a floor of | 45 s, 240 s | 45 s, 180 s | 45 s, 150 s |
| Gas drain | 6 s per second | 12 s per second | 20 s per second |
| Laser touch / laser stays off | 5 s / 15 s | 10 s / 10 s | 20 s / 6 s |
| ORACLE question | free | 5 s | 10 s |
| Hint | 10 s | 20 s | 40 s |
| Wrong breaker / wrong valves or frequency | 8 s / 5 s | 15 s / 10 s | 30 s / 20 s |
| Score multiplier | x0.6 | x1.0 | x1.4 |

All the numbers live in `scripts/rules.gd` (`LEVELS`); the manuals have a "Levels" entry that `tests/test_kb_sync.gd` keeps in sync with it. The numbers are estimates and have not been tuned by play.

## Modifiers

Three optional extras on the main menu, under the levels. They can be combined, they are remembered in the save file, and each one switched on raises the score multiplier.

| Modifier | What it does | Score |
|---|---|---|
| **Blackout** | The corridor lights flicker unevenly and one cuts out for a third of a second now and then (never below 35% except in those dips, so you can still walk). Each shift starts the gas vents at a different point of their cycle, so you cannot learn the timing. A retry of the same shift keeps its timing. | x1.15 |
| **Hardcore** | One failed shift ends the run: a **RUN OVER** screen shows the run score you lost, the score is cleared, and there are **no retries** (hold R shows "NO RETRIES IN HARDCORE" and the pause menu's Retry button is greyed out). Your saved best run is kept. | x1.25 |
| **Speedrun** | A **PAR** time is shown under the reserve: half the shift's starting reserve (3:00 on shift 1 of Engineer), with a count of the time left to beat it. Finishing within par adds 100 points plus 1 per second under it (before the multipliers); the win screen shows it. Time is the reserve you used, penalties included. | x1.0 |

Modifiers multiply with the level's score multiplier (for example Survivor with Hardcore is x1.4 x 1.25). The numbers live in `scripts/rules.gd` and the manuals have a "Modifiers" entry kept in sync by `tests/test_kb_sync.gd`. They are estimates and have not been tuned by play.

## The Cryo Bay (optional story)

West of the crew quarters, on the way to the reboot terminal at the far west end, an open door leads to the **Cryo Bay**: six pods with the sleeping crew (their name plates are on the pods) and four terminals, **CREW LOG 1 to 4**, that tell what happened to the station. The pods glow red while the station is broken and turn cyan as you repair it. Press **E** at a terminal to read a log; like the manuals it pauses the game, so reading costs no reserve. The logs are story only: no rule, score or puzzle answer, and nothing in the room changes the game. Which logs you have read is remembered in the save file. It is on the way to the reboot terminal, so you pass its door when you finish; stepping in to read a log costs only a few seconds of walking.

## Sound and feel

**Theme song:** a 29-second, 100 BPM loop in two layers that play in sync. The calm layer is always on: a slow heartbeat, a rasping string pad on clashing chords, thin bells and a metal impact with long echoes. The tense layer is already faintly there when a shift begins and swells in as the danger rises (the reserve draining, a gas vent open near you, the live laser grid close, or a hit you just took) and fades out again when you are safe: a stalking ostinato built on a flat second and a tritone, a second heartbeat, hi-hat ticks, a distant alarm and a rising hiss. It plays over the opening intro and the menu (calm only) and carries on into the shift without restarting. It is composed and synthesised in code when the game opens (about half a second, no audio file); every pitched note is A3 or higher and there is no sustained low tone, only short heartbeat thumps. It fades in and stops in pause and on the results screens. **B** turns it off, **N** mutes everything. It is verified by tests for length, loop seam, loudness and pitch range; how it sounds has not been judged by a person yet.

**Survival atmosphere:** on top of the music the station makes sounds now and then, never as a constant drone: metal groans and distant bangs every 9 to 21 seconds, a harsh two-beep alarm every 14 seconds until the first system is repaired, electric crackle when you are near the live laser grid, a frightened heartbeat in the last 45 seconds of reserve (on top of the clock tick), breathing inside the helmet (faster as the reserve runs low), ventilation fans that wind down while the station is broken and spin up and whoosh once you repair it, a heavy sliding sound when a door unlocks and a dull clunk if you walk up to a locked one, and a steady hiss while a gas vent is open near you. All are generated in code, quiet, and switched off by **N**. They have no effect on the rules.

All sound is generated in code when the game starts (no audio files): no background hum or any continuous sound, only short effects: click on a correct breaker, hiss when a console opens, chime when a system is repaired, buzz on a mistake, rising notes on a win, a falling tone on a loss, footsteps, and a soft clock tick-tock once a second when the reserve is under a minute (twice as fast under 20 seconds). **N** mutes everything. Sound is feedback only; no rule depends on it.

Feel: a gentle head bob and footsteps while walking (each footstep sound plays when a foot lands: the head dips and the legs are at their widest), the view rises and fades in from black at the start of every shift or retry, the object you aim at glows and pulses smoothly, and consoles and breakers push in when pressed.

## The walk (corridor, doors and hazards)

The station is one long corridor (about 70 m) with the crew quarters, Power, Oxygen, Comms and Cooling rooms along it, 12 m apart (the optional Cryo Bay and the reboot terminal are at the far west end), so a shift is a real walk there and back.

- **Doors in order:** the Oxygen door stays locked until Power is repaired, the Comms door until Oxygen is repaired, and the Cooling door until Comms is repaired. Each shows what it needs and slides open when its system is repaired.
- **Two gas vents** (one between the quarters and Power, one between Power and Oxygen): a lamp above each is grey (quiet), amber (warning) or red (venting). Standing in venting gas costs 12 reserve seconds per second. Wait for grey.
- **Hazards grow with the shift:** each later shift the gas vents are quiet 0.5 s less (to a floor of 1.5 s), vent 0.5 s longer (to 9 s) and spread 1 m further (to 10 m), and a wall switch keeps a laser grid off 1 s less (never under half its time). From shift 3 a **second laser grid** blocks the corridor between Comms and Cooling, with its own two switches. Shift 1 is exactly as before. The notice at the start of a shift says "HAZARDS GROW", or "A SECOND LASER GRID" on shift 3.
- **Laser grid** (between Oxygen and Comms; the second one, from shift 3, is between Comms and Cooling): six red beams that are a solid wall, so you cannot walk through. Touching them costs 10 reserve seconds. A **wall switch** on each side (press **E**) turns the grid off for 10 seconds; it flickers before it switches back on, and it waits while anyone stands in the beams.
- **ORACLE costs time:** every question asked to ORACLE costs 5 reserve seconds (never the last second). The manuals (**M**) and the hint button's own 20 s cost are separate; the manuals are free.
- Hazards use the shift's real reserve and are not counted as puzzle mistakes. They start in a fixed state each attempt, so a retry plays the same walk.
- **Waking up in bed:** a new run starts with you lying in the lower bunk, eyes shut, looking up at the bunk above. Your eyes open, you blink, sit up, turn toward the room and stand, facing the door, about 6 seconds in all, with a pulsing red alarm. Movement, looking and interacting are locked until you are up; a key press skips it after 2 seconds. Only the very first shift of a run does this: after a shift, or on a retry, you are already awake and simply fade in standing by the bunk.

Not tuned yet: made harder after a friend found it easy (shorter reserve, harsher gas, a blocking laser, paid ORACLE questions). The new numbers were chosen by reasoning, not by playing; walking the corridor takes about 10 s one way.

## Window and full screen

The interface is designed at 1280x720 and scales with the window (Godot `canvas_items` stretch, aspect "expand"), so text, buttons and panels grow in full screen instead of staying small. The 3D view renders at the window's full resolution. Checked by rendering at 1280x720 and 2560x1440.

## Opening screen

A survival-style title screen drawn in code: drifting stars, a dark planet with a glowing rim, a satellite crossing the sky, a breathing red emergency glow, a flickering title, a blinking "LIFE SUPPORT FAILING" warning and a status panel with a draining oxygen gauge (decoration only). When the game window opens, a short typed intro plays first ("DAY 412 ... YOU ARE THE LAST ONE AWAKE."); any key or click skips it. It plays once per launch, not every time you return to the menu.

## Third person view and shift themes

**V** switches between first person (default) and an over-the-shoulder third person view with a classic astronaut built from simple shapes (bulky white pressure suit, big round helmet with a gold reflective visor, chest control box with buttons and hoses, flag and mission patches, grey cuffs and knee rings, thick gloves and chunky boots; no backpack). Only the camera changes: collision, reach and rules are identical. The camera is pulled in front of walls so it never clips, and the body is hidden when a wall squeezes the camera against it. **C** puts the camera in front of the character, looking back at its face (you can still walk, but nothing can be aimed at or used in that view). Your choice is kept across shifts and retries.

Each shift has its own colour theme (walls, floor, ceiling, haze and hub light): Midnight, Emerald, Ember, Orchid, Steel, then repeating. A retry keeps the shift's theme. Meaning colours never change: red is faulted, cyan is repaired. The theme name appears briefly at the start of the shift.

## ORACLE

Press **H** and ask, for example, "How do I fix the power breakers?". It shows the matching manual text (with ids) under every answer. It cannot see the values in your rooms and cannot change the game.

- **Rules and numbers are always answered exactly, in code, never by the AI** (header: *Exact answer from the manual*). Tell it what you read, e.g. "B1 is 277 V, B2 is 480 V, B3 is 208 V, B4 is 400 V, protocol B, restore mode, which first?" and it works out the flip order. Comms frequencies are calculated from the beacon count. If you name no protocol it shows both. This design is because the small AI model reversed orders and reused example numbers when tested.
- **Other questions** (scoring, what to do next, controls, retrying): *Basic Manual Mode* shows the matching manual answer (no setup needed). Say "hello" or "help" for topics, or "I am stuck" for first steps.
- **Optional:** with a local model through Ollama, those general questions can get a short written answer (header *Local AI*), checked by code guards. See `docs/OFFLINE_AI_SETUP.md`. Everything stays on your computer.

## How it is built

| Part | Files |
|---|---|
| Rules and constants (single source of truth) | `scripts/rules.gd` |
| Puzzles (seeded, pure data) and checks | `scripts/puzzle_generator.gd`, `scripts/puzzle_validators.gd` |
| Game state, reserve, win/fail | `scripts/game_manager.gd`, `scripts/score_manager.gd` |
| World, player, interaction | `scripts/station_builder.gd`, `scripts/player_controller.gd`, `scripts/interactable.gd`, `scripts/door_gate.gd`, `scripts/hazard_zone.gd`, `scripts/laser_grid.gd`, `scripts/shift_theme.gd` |
| Sound and menu | `scripts/sound_bank.gd`, `scripts/theme_music.gd`, `scripts/menu_screen.gd` |
| UI and flow | `scripts/main.gd`, `scripts/ui_puzzle_panels.gd`, `scripts/ui_manuals_panel.gd` |
| Manuals and saving | `data/game_knowledge.json`, `scripts/knowledge_base.gd`, `scripts/save_manager.gd` |
| ORACLE | `scripts/assistant/` (retriever, logic, Ollama client, controller, panel) |

Everything is created in code from one tiny scene. Retrieval is plain keyword scoring (no embeddings, no server). The security boundary is in code: ORACLE output is only displayed.

## Tests

```
./tests/run_all.sh        # needs `godot` on PATH
```
25 headless test files, 1019 checks, all passing at the time of writing (see `docs/TEST_REPORT.md`). A few tests print an ERROR/WARNING on purpose.

## Changes since the original spec

- **Protocol A/B (added after playtesting):** the spec had one fixed rule set, so once learned the manuals and ORACLE had nothing left to teach. Every shift now runs under protocol A or B, which changes the Power order, the Oxygen table and the Comms formula. The protocol is shown in the checklist but is not given to ORACLE.
- **Mission briefing:** the intro card is now a short story and no longer lists the rules.
- **Escalating shifts and run total (added after playtesting):** reserve drops 45 s per shift (down to a floor that depends on the level), the run total adds the shift scores, and the best run is saved. The spec had identical shifts.
- **Guided first shift and protocol board:** shift 1 is always Protocol A with a "what to do next" line; a big sign in the crew quarters shows the protocol.
- **The walk (added after playtesting feedback):** the compact hub became a bedroom start, a long corridor, far rooms, doors that unlock in order, and gas and spark hazards (see "The walk").
- **Redesigned look (after playtesting feedback):** every door has a header sign, a frame and a light that turn from red to cyan when its system is repaired; two matching boards flank the middle door (the protocol, and how to get help); each room has a tinted floor and a ceiling strip, and the room lights up (bright cyan strip and floor) when repaired; the hub light flickers, and under a minute of reserve the station pulses red with a red screen-edge vignette (visual only, rules unchanged); breaker ratings are printed on the breakers; each room has one tidy display panel; the reboot terminal is labelled and turns cyan when ready.
- **Modifiers (added later):** Blackout, Hardcore and Speedrun switches on the menu (see "Modifiers").
- **Cryo Bay (added later):** an optional room with the sleeping crew and four story logs (see "The Cryo Bay").
- **Hazards that grow (added later):** vents and laser switches get harsher each shift, and a second laser grid appears from shift 3 (see "The walk").
- **Fourth system, Cooling (added later):** a reactor room past Comms with a CORE TEMP and a REACTOR state; the coolant flow is a formula that differs by protocol, and the core cools from orange to cyan when repaired. Reboot now needs 4/4.
- **Hints:** ORACLE's Get a hint button costs reserve time (20 s on Engineer). The hint is computed by the game, not the AI.
- **Harder walk (after a friend found it easy):** a laser grid blocks the corridor until a wall switch turns it off, gas is harsher, and ORACLE questions cost reserve time.
- **Levels:** a Rookie / Engineer / Survivor selector on the menu changes the reserve, hazards, help costs and score (see "Levels").
- **Sound:** a survival soundscape and a two-layer theme song that gets more tense with danger (see "Sound and feel").
- **Look:** a classic astronaut character (third person, **V**, and a front view, **C**), a proper bunk bed, and a station look with windows onto a planet, ceiling pipes, ribs and floor guide lights.
- **Waking up:** you wake in bed only on the first shift of a run; later shifts and retries start you already awake.
- **Smoother play:** anti-aliasing, a soft glow, and acceleration on movement.

## Developer launch option

`godot --path . -- --shift=3` starts a new game on shift 3 (any shift from 1 to 99), so the later, harder shifts can be tried without winning the earlier ones. It is not shown anywhere in the game.

## Developer tools

`tools/screenshot.gd` renders the station from several viewpoints to PNG files (needs a real window, not `--headless`):
```
godot --path . -s res://tools/screenshot.gd -- /path/to/output/folder            # as it starts
godot --path . -s res://tools/screenshot.gd -- /path/to/output/folder repaired   # all systems repaired
```
Others in `tools/` (all need a real window): `menu_shot.gd` (the main menu; add `plain` to skip the intro), `avatar_shot.gd` (the astronaut from the front, side and back), `audio_probe.gd` (prints how loud the game is with and without danger), and `export_theme.gd` (saves the theme song as a WAV).

## Known limitations

- The local model (qwen2.5:1.5b) was tested headless with real questions, not by a person in the game window. It is used only for general questions, because it got puzzle rules wrong in testing (see `docs/TEST_REPORT.md` 2a). Its wording on general questions can still be off.
- No Windows build or Windows run has been done; export templates were not installed here.
- Fog, wall display plates and the Main Menu / Manuals / ORACLE windows have not been checked by a person in a window.
- Frame rate was not measured. Sound effects are simple generated tones (see below), and how they sound has not been judged by a person yet. One fixed station layout; only the puzzle values change.
- Saved with Godot 4.7.2; older Godot 4 versions are untested.

## Licenses

All code and text are original to this project; no third-party assets are included. Godot is MIT licensed. See `LICENSES.md`.
