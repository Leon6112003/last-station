# LAST STATION

A short first-person repair puzzler for Godot 4 (GDScript only). The station is failing: you have 6 minutes of oxygen reserve to repair **Power**, **Oxygen** and **Comms**, then reboot the station. An offline help assistant, **ORACLE**, answers questions from the station manuals.

Built as a two-day-scope prototype. Specification: `AGENTS.md` and `REQUIREMENTS.md`. Test evidence: `docs/TEST_REPORT.md`.

## Run

1. Install Godot 4 (Standard edition). Developed and tested with **4.7.2.stable** on macOS.
2. Open Godot, **Import** `project.godot`, press **F5**.
3. Windows build and export steps: `docs/WINDOWS_SETUP.md` (not verified on Windows; no `.exe` has been built).

## Purpose

The Last Station has lost power, the crew are asleep in hibernation and the oxygen is running out. ORACLE, the station's old help system, remembers how every system works. You repair Power, Oxygen and Comms before the reserve reaches zero.

As a project it is a demonstration of a **RAG assistant inside a game**: the rules live in written manuals, ORACLE finds the right manual by keyword and answers from it, and the game is built so the AI can never change the game.

## How to play

1. Press **Play**. You wake up in the crew quarters, facing the door and the **PROTOCOL** sign beside it. The oxygen reserve (6:00 on shift 1) starts when you first move. **Shift 1 is a guided shift:** it always uses Protocol A and a line at the bottom tells you what to do next.
2. The top-left checklist shows what is left and the current **PROTOCOL (A or B)**. Walk the corridor east to the three rooms and repair each system, then walk all the way back west and press **E** on the reboot terminal.
3. Aim the `+` at a terminal until `E — ...` appears, then press **E**.
4. **The game does not tell you the rules.** Read the panels in each room, then press **M** (manuals) or **H** (ORACLE) to look up what to do. The protocol changes the rules, so check it each shift.

**Score** = 300 + (reserve seconds left ÷ 2) − 50 per retry (retry penalty capped at 150). Maximum 540 on shift 1. Your best shift score is saved.

**Runs get harder.** Press **Next Shift** after a win to keep going: every shift has 45 seconds less reserve (360, 315, 270, 225, then 180 at the lowest), and your **run total** adds up the score of each shift you clear. Your best run is saved.

**Hints.** In ORACLE (press H) the **Get a hint** button costs 20 seconds of reserve. It tells you the next system to repair and which protocol rules apply, but never the answer. (Typing "hint" to ORACLE does not use one.)

<details><summary>Spoiler: the full rules (the same text is in the in-game manuals)</summary>

| Room | Protocol A | Protocol B |
|---|---|---|
| **POWER** (left): flip the 4 breakers by voltage | `RESTORE` lowest first, `SHED` highest first | reversed: `RESTORE` highest first, `SHED` lowest first |
| **OXYGEN** (middle): station mode, then valves A/B/C | NIGHT 30/40/50, DAY 50/60/70, EMERGENCY 70/80/90 | NIGHT 40/50/60, DAY 60/70/80, EMERGENCY 80/90/100 |
| **COMMS** (right): count the lit beacons | 100 + 20 × lit MHz | 100 + 10 × lit MHz |

A wrong breaker costs 15 s; wrong valves or a wrong frequency cost 10 s.
</details>

## Controls

| Key | Action |
|---|---|
| W A S D / mouse | Move / look |
| E | Interact |
| M | Manuals (pauses the game) |
| H | ORACLE help chat (pauses the game) |
| V | Switch first / third person view |
| B | Theme song on / off |
| N | All sound on / off |
| Esc | Pause, or close a panel |
| Hold R (1 s) | Retry this shift (same station, **new puzzle values**) |

## Sound and feel

**Theme song:** a slow, tense 29-second loop with a survival mood plays over the opening intro and the menu and carries on into the shift without restarting (detuned pads that shimmer, harmony with semitone clashes, a muted nervous pulse, a sonar ping with long echoes, a thin bell melody, and a hiss that swells before each loop point). It is composed and synthesised in code when the game opens (about half a second, no audio file), stays in the middle and upper register with no low drone, fades in, and stops in pause and on the results screens. **B** turns it off, **N** mutes everything. It is verified by tests for length, loop seam, loudness and pitch range; how it sounds has not been judged by a person yet.

All sound is generated in code when the game starts (no audio files): no background hum or any continuous sound, only short effects: click on a correct breaker, hiss when a console opens, chime when a system is repaired, buzz on a mistake, rising notes on a win, a falling tone on a loss, footsteps, and a soft clock tick-tock once a second when the reserve is under a minute (twice as fast under 20 seconds). **N** mutes everything. Sound is feedback only; no rule depends on it.

Feel: a gentle head bob and footsteps while walking (each footstep sound plays when a foot lands: the head dips and the legs are at their widest), the view rises and fades in from black at the start of every shift or retry, the object you aim at glows and pulses smoothly, and consoles and breakers push in when pressed.

## The walk (corridor, doors and hazards)

The station is one long corridor (about 46 m) with the crew quarters, Power, Oxygen and Comms rooms along it, 12 m apart, and the reboot terminal at the far west end, so a shift is a real walk there and back.

- **Doors in order:** the Oxygen door stays locked until Power is repaired, and the Comms door stays locked until Oxygen is repaired. Each shows what it needs and slides open when its system is repaired.
- **Two gas vents** (one between the quarters and Power, one between Power and Oxygen): a lamp above each is grey (quiet), amber (warning) or red (venting). Standing in venting gas costs 12 reserve seconds per second. Wait for grey.
- **Laser grid** (between Oxygen and Comms): six red beams that are a solid wall, so you cannot walk through. Touching them costs 10 reserve seconds. A **wall switch** on each side (press **E**) turns the grid off for 10 seconds; it flickers before it switches back on, and it waits while anyone stands in the beams.
- **ORACLE costs time:** every question asked to ORACLE costs 5 reserve seconds (never the last second). The manuals (**M**) and the hint button's own 20 s cost are separate; the manuals are free.
- Hazards use the shift's real reserve and are not counted as puzzle mistakes. They start in a fixed state each attempt, so a retry plays the same walk.
- **Waking up in bed:** a new run starts with you lying in the lower bunk, eyes shut, looking up at the bunk above. Your eyes open, you blink, sit up, turn toward the room and stand, facing the door, about 6 seconds in all, with a pulsing red alarm. Movement, looking and interacting are locked until you are up; a key press skips it after 2 seconds. Retries and later shifts use a shorter version (about 3 seconds).

Not tuned yet: made harder after a friend found it easy (shorter reserve, harsher gas, a blocking laser, paid ORACLE questions). The new numbers were chosen by reasoning, not by playing; walking the corridor takes about 10 s one way.

## Window and full screen

The interface is designed at 1280x720 and scales with the window (Godot `canvas_items` stretch, aspect "expand"), so text, buttons and panels grow in full screen instead of staying small. The 3D view renders at the window's full resolution. Checked by rendering at 1280x720 and 2560x1440.

## Opening screen

A survival-style title screen drawn in code: drifting stars, a dark planet with a glowing rim, a satellite crossing the sky, a breathing red emergency glow, a flickering title, a blinking "LIFE SUPPORT FAILING" warning and a status panel with a draining oxygen gauge (decoration only). When the game window opens, a short typed intro plays first ("DAY 412 ... YOU ARE THE LAST ONE AWAKE."); any key or click skips it. It plays once per launch, not every time you return to the menu.

## Third person view and shift themes

**V** switches between first person (default) and an over-the-shoulder third person view with a space station worker built from simple shapes (white helmet with a glowing visor, orange work suit with a chest panel, gloves and boots). Only the camera changes: collision, reach and rules are identical. The camera is pulled in front of walls so it never clips, and the body is hidden when a wall squeezes the camera against it. Your choice is kept across shifts and retries.

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
| World, player, interaction | `scripts/station_builder.gd`, `scripts/player_controller.gd`, `scripts/interactable.gd` |
| UI and flow | `scripts/main.gd`, `scripts/ui_puzzle_panels.gd`, `scripts/ui_manuals_panel.gd` |
| Manuals and saving | `data/game_knowledge.json`, `scripts/knowledge_base.gd`, `scripts/save_manager.gd` |
| ORACLE | `scripts/assistant/` (retriever, logic, Ollama client, controller, panel) |

Everything is created in code from one tiny scene. Retrieval is plain keyword scoring (no embeddings, no server). The security boundary is in code: ORACLE output is only displayed.

## Tests

```
./tests/run_all.sh        # needs `godot` on PATH
```
20 headless test files, 725 checks, all passing at the time of writing (see `docs/TEST_REPORT.md`). A few tests print an ERROR/WARNING on purpose.

## Changes since the original spec

- **Protocol A/B (added after playtesting):** the spec had one fixed rule set, so once learned the manuals and ORACLE had nothing left to teach. Every shift now runs under protocol A or B, which changes the Power order, the Oxygen table and the Comms formula. The protocol is shown in the checklist but is not given to ORACLE.
- **Mission briefing:** the intro card is now a short story and no longer lists the rules.
- **Escalating shifts and run total (added after playtesting):** reserve drops 60 s per shift (minimum 240 s), the run total adds the shift scores, and the best run is saved. The spec had identical shifts.
- **Guided first shift and protocol board:** shift 1 is always Protocol A with a "what to do next" line; a big sign in the crew quarters shows the protocol.
- **The walk (added after playtesting feedback):** the compact hub became a bedroom start, a long corridor, three far rooms, doors that unlock in order, and gas and spark hazards (see "The walk").
- **Redesigned look (after playtesting feedback):** every door has a header sign, a frame and a light that turn from red to cyan when its system is repaired; two matching boards flank the middle door (the protocol, and how to get help); each room has a tinted floor and a ceiling strip, and the room lights up (bright cyan strip and floor) when repaired; the hub light flickers, and under a minute of reserve the station pulses red with a red screen-edge vignette (visual only, rules unchanged); breaker ratings are printed on the breakers; each room has one tidy display panel; the reboot terminal is labelled and turns cyan when ready.
- **Hints:** ORACLE's Get a hint button costs 20 s of reserve. The hint is computed by the game, not the AI.

## Developer tool: screenshots

`tools/screenshot.gd` renders the station from several viewpoints to PNG files (needs a real window, not `--headless`):
```
godot --path . -s res://tools/screenshot.gd -- /path/to/output/folder            # as it starts
godot --path . -s res://tools/screenshot.gd -- /path/to/output/folder repaired   # all systems repaired
```

## Known limitations

- The local model (qwen2.5:1.5b) was tested headless with real questions, not by a person in the game window. It is used only for general questions, because it got puzzle rules wrong in testing (see `docs/TEST_REPORT.md` 2a). Its wording on general questions can still be off.
- No Windows build or Windows run has been done; export templates were not installed here.
- Fog, wall display plates and the Main Menu / Manuals / ORACLE windows have not been checked by a person in a window.
- Frame rate was not measured. Sound effects are simple generated tones (see below), and how they sound has not been judged by a person yet. One fixed station layout; only the puzzle values change.
- Saved with Godot 4.7.2; older Godot 4 versions are untested.

## Licenses

All code and text are original to this project; no third-party assets are included. Godot is MIT licensed. See `LICENSES.md`.
