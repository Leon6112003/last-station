# LAST STATION: Handoff report

Format from `AGENTS.md` section 8. Everything here is something that was actually run or reported; anything else is listed under NOT VERIFIED. Details and per-file counts are in `docs/TEST_REPORT.md`.

## IMPLEMENTED

**Core game (required)**
- First-person (and third-person) 3D repair puzzler, all built from code with Godot primitives. One tiny scene runs `main.gd`.
- Four systems to repair along a long corridor, each with its own puzzle: **Power** (flip breakers in an order), **Oxygen** (set three valves from a table), **Comms** (tune a frequency from a formula) and **Cooling** (set the coolant flow from a formula). The rules change with **Protocol A or B**, so the manuals are needed.
- A final **reboot code** (a different kind of puzzle): a pad sequence is flashed and you repeat it, in the same order on protocol A and in reverse on B.
- Oxygen **reserve** countdown, mistakes and penalties, win and fail, hold-R retry (the puzzle values are re-rolled), results screen, Next Shift (a new seed, less reserve), run total and best scores saved.
- Corridor hazards: gas vents, a laser grid with wall switches (a second grid from shift 3), and gas leaks at the Oxygen and (in a SURGE) Cooling consoles. They grow harsher each shift, and repairing a system switches off the hazard it was feeding.
- **ORACLE**, an offline help assistant: keyword retrieval over 30 written manual entries, exact answers in code for rules and numbers, an optional local model (Ollama) for general questions, and the exact manual text always shown. **The AI never changes the game** (the boundary is in code, with injection tests). It is rule-based retrieval, not machine learning.

**Extras**
- **Adaptive difficulty:** a fixed, rule-based rule (not machine learning) makes the next shift harder, easier or the same from how the last one went (reserve used, mistakes, retries), shown on the results screen and switchable in Settings.
- Three levels (Rookie, Engineer, Survivor) and three optional modifiers (Blackout, Hardcore, Speedrun) with score multipliers.
- Settings: separate music and effects volume, mouse speed, rebindable keys, colour-blind cues (a cross or tick, words by the gas lamps) and sound captions (also shown when sound is muted).
- Generated sound effects and a two-layer theme song that gets more tense with danger (no audio files), a wake-up-in-bed opening, an astronaut character with a front view, an optional Cryo Bay with four story logs, and a textured station with props.

## HOW TO RUN
- Godot **4.7.2** (Standard edition, GL Compatibility renderer), macOS. Open `project.godot` in Godot and press **F5**, or:
```
cd LAST_STATION && godot --path .
```
- Developer options (not shown in the game): `godot --path . -- --shift=3` starts on shift 3.
- Tests: `./tests/run_all.sh` (needs `godot` on the PATH).
- Everything works offline. ORACLE's local model is optional: see `docs/OFFLINE_AI_SETUP.md`. Windows steps: `docs/WINDOWS_SETUP.md`.

## TESTED
- **30 headless test files, 1259 checks, all passing** on the development Mac (Godot 4.7.2). They cover the puzzles and scoring, determinism, the retriever and the ORACLE injection boundary, the real main scene through whole shifts and menu round trips, layout at 1280x720, 1024x576 and 1920x1080, saving, settings and rebinding, and every feature added later.
- **Rendered screenshots** of the station, menu, Settings, the reboot panel and the new rooms were reviewed (`tools/*.gd`), and several layout problems were found and fixed this way.
- **Measured in a real window** on an Apple M3 (`tools/perf_probe.gd`): about 8 to 9 ms per frame in five views.
- **Played by the project owner:** earlier versions throughout the project, and a ten-minute route covering the newest features, reported as fine.
- **ORACLE with a real local model** (qwen2.5:1.5b via Ollama) was tested headless, with the problems found and the design change recorded in the test report.

## NOT VERIFIED
- **No Windows build exists** (the export templates are not installed) and nothing was run on Windows.
- **Frame rate on a weaker laptop** is not measured.
- **The local model after the manuals grew to 30 entries** was not re-run. The built-in manual mode needs no model and is tested.
- **How it sounds:** audio was never judged by me (I cannot hear it). The project owner's feedback on the music was mixed, and the latest version was not rated separately.
- **Balance:** the reserve, hazard growth, level and modifier numbers, the Speedrun par and the adaptive-difficulty thresholds are estimates, not tuned by play.
- **Colour-blind cues** were not checked by a colour-blind player, and key rebinding was tested with simulated key events.

## LIMITATIONS
- One fixed station layout; only the puzzle values, protocol, hazards and theme change.
- The in-world signs and the how-to-play text show the **default keys** even after rebinding (the help line, prompts and guidance follow the new keys).
- The best score is a single number across all levels (the level multiplier keeps it comparable).
- Many small boxes make up the station (up to about 440 draw calls in the busiest view). Fine on the development Mac, unknown on weak hardware.
- The ORACLE local model can word general answers badly; the exact manual text is always shown next to it.

## NEXT (max 3)
1. Export and test a Windows build, and measure frame rate on a weaker machine.
2. Play-test with several people and tune the level, hazard and modifier numbers.
3. Merge the many plain boxes into fewer meshes if performance needs it.
