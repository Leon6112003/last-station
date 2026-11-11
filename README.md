# LAST STATION

A short first-person repair puzzler for Godot 4 (GDScript only). The station is failing: you have 8 minutes of oxygen reserve to repair **Power**, **Oxygen** and **Comms**, then reboot the station. An offline help assistant, **ORACLE**, answers questions from the station manuals.

Built as a two-day-scope prototype. Specification: `AGENTS.md` and `REQUIREMENTS.md`. Test evidence: `docs/TEST_REPORT.md`.

## Run

1. Install Godot 4 (Standard edition). Developed and tested with **4.7.2.stable** on macOS.
2. Open Godot, **Import** `project.godot`, press **F5**.
3. Windows build and export steps: `docs/WINDOWS_SETUP.md` (not verified on Windows; no `.exe` has been built).

## Purpose

The Last Station has lost power, the crew are asleep in hibernation and the oxygen is running out. ORACLE, the station's old help system, remembers how every system works. You repair Power, Oxygen and Comms before the reserve reaches zero.

As a project it is a demonstration of a **RAG assistant inside a game**: the rules live in written manuals, ORACLE finds the right manual by keyword and answers from it, and the game is built so the AI can never change the game.

## How to play

1. Press **Play**. You spawn in the hub, facing a big **PROTOCOL** sign. The oxygen reserve (8:00 on shift 1) starts when you first move. **Shift 1 is a guided shift:** it always uses Protocol A and a line at the bottom tells you what to do next.
2. The top-left checklist shows what is left and the current **PROTOCOL (A or B)**. Repair the three systems, then press **E** on the reboot terminal in the hub.
3. Aim the `+` at a terminal until `E — ...` appears, then press **E**.
4. **The game does not tell you the rules.** Read the panels in each room, then press **M** (manuals) or **H** (ORACLE) to look up what to do. The protocol changes the rules, so check it each shift.

**Score** = 300 + (reserve seconds left ÷ 2) − 50 per retry (retry penalty capped at 150). Maximum 540 on shift 1. Your best shift score is saved.

**Runs get harder.** Press **Next Shift** after a win to keep going: every shift has 60 seconds less reserve (480, 420, 360, 300, then 240 at the lowest), and your **run total** adds up the score of each shift you clear. Your best run is saved.

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
| Esc | Pause, or close a panel |
| Hold R (1 s) | Retry this shift (same station, **new puzzle values**) |

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
14 headless test files, 506 checks, all passing at the time of writing (see `docs/TEST_REPORT.md`). A few tests print an ERROR/WARNING on purpose.

## Changes since the original spec

- **Protocol A/B (added after playtesting):** the spec had one fixed rule set, so once learned the manuals and ORACLE had nothing left to teach. Every shift now runs under protocol A or B, which changes the Power order, the Oxygen table and the Comms formula. The protocol is shown in the checklist but is not given to ORACLE.
- **Mission briefing:** the intro card is now a short story and no longer lists the rules.
- **Escalating shifts and run total (added after playtesting):** reserve drops 60 s per shift (minimum 240 s), the run total adds the shift scores, and the best run is saved. The spec had identical shifts.
- **Guided first shift and hub protocol board:** shift 1 is always Protocol A with a "what to do next" line; a big sign in the hub shows the protocol.
- **Redesigned look (after playtesting feedback):** every door has a header sign, a frame and a light that turn from red to cyan when its system is repaired; two matching boards flank the middle door (the protocol, and how to get help); each room has a tinted floor; breaker ratings are printed on the breakers; each room has one tidy display panel; the reboot terminal is labelled and turns cyan when ready.
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
- Frame rate was not measured. No sound. One fixed station layout; only the puzzle values change.
- Saved with Godot 4.7.2; older Godot 4 versions are untested.

## Licenses

All code and text are original to this project; no third-party assets are included. Godot is MIT licensed. See `LICENSES.md`.
