# LAST STATION: Test Report

Date: 2026-11-11 · Godot 4.7.2.stable (official) · macOS (Apple silicon) · renderer: GL Compatibility · Ollama app 0.40.16 with qwen2.5:1.5b

Labels: **PASS** = run and observed to pass · **FAIL** = run and failed · **NOT RUN** = not done, with the reason.
Nothing here is claimed unless it was actually run.

## 1. Automated tests (headless)

Run with `./tests/run_all.sh` (needs `godot` on PATH). All 14 files ended with `ALL PASS`: **506 checks, 0 failures**.

| File | Checks | What it covers |
|---|---:|---|
| `test_puzzles.gd` | 51 | 100 seeds × 3 attempts generate valid puzzles (both protocols occur); each puzzle has exactly one accepted answer; protocol B rules for all three systems; determinism; retry re-rolls (100/100 seeds changed); penalties (15 s / 10 s); reserve clamps at 0; win, fail, retry rules |
| `test_score.gd` | 15 | 450 / 310 / 150 / 540 examples, caps, never negative |
| `test_retrieval.gd` | 34 | right manual ranks first for 10 questions (incl. "hello", "I am stuck"); max 3 results; stable; sorted; unrelated question returns nothing; tie order; 450-char excerpts; Basic Manual Mode answers pick the right protocol/mode sentence and never show only one protocol when none is named |
| `test_kb_sync.gd` | 81 | 19 manual entries; every number in `rules.gd` (both protocols, including each oxygen table row) appears in the matching entry; no run-specific values; loader survives bad input |
| `test_injection.gd` | 98 | snapshot has only allowed keys; 4 injection strings change no game state; fake source ids never shown; 1,200-char question cut to 300; prompt delimiters cannot be spoofed; system prompt is fixed; busy lock; every failure path falls back; answers cut at 800 chars |
| `test_oracle_ui.gd` | 23 | H opens ORACLE with a real key event; pauses game and reserve; answers shown with manual excerpts; BBCode shown literally; Send disabled while "thinking"; R and M ignored while open; Esc and Close work; leaving for the menu closes it |
| `test_ollama_down.gd` | 8 | the REAL Ollama client against `127.0.0.1:11434`. It handles both cases: with no server it must fail cleanly and fall back (this was run and passed before Ollama was installed); with the server running it must return a labelled local answer within 800 characters (run and passed on 2026-11-11 with qwen2.5:1.5b) |
| `test_progression.gd` | 46 | reserve per shift (480, 420, 360, 240 floor); shift 1 always protocol A even after retries, later shifts use both; run total adds shift scores and resets for a new run; hints (cost 20 s, counted, never contain the answer, free when all repaired, refused without charge when the reserve is too low); best run saved; in the real scene: hub board text, coach line per step on shift 1 only, win screen shows run total / hints / next reserve, the Get a hint button works, and typing "hint" or "use a hint now" never spends one |
| `test_flow.gd` | 28 | a full shift through the real main scene: early reboot refused, surge, three repairs, win, best score saved, Next Shift, fail, Retry, pause/resume, checklist ticks |
| `test_menu_flow.gd` | 57 | starts in the Main Menu; **3 consecutive cycles** (play, win, Next Shift, fail, retry, pause, Main Menu) with identical node counts (40, 40, 40) and 0 orphans; hold-R retry (short press cancels, 1 s retries once); Manuals pause the reserve; real M and Esc key events; intro card once |
| `test_save.gd` | 10 | best score, intro flag, persistence, corrupt file, unwritable path |
| `test_layout.gd` | 27 | at 1280×720, 1024×576 and 1920×1080 (the game runs inside a sized viewport, because headless ignores window size): every button of How to Play, the intro card, pause, win, fail and the main menu is inside the window; the Manuals and ORACLE panels fit; How to Play fully hides the menu behind it. Added after a bug pushed the Back button off the bottom of the How to Play page |
| `test_smoke.gd` | 21 | station builds: 7 interactables, lights, solid bodies, player; a header above each doorway with 2 m headroom; door status materials start red; one protocol sign showing the shift's protocol; each breaker has its rating on it |
| `test_walk.gd` | 7 | physics: walks through a doorway, stopped by north and west walls, stays on the floor, aiming selects the console |

Some tests print an `ERROR` or `WARNING` line on purpose (they feed corrupt or missing files to the loaders). The test still passes.

Launch check: `godot --headless --path . --quit-after 60` printed no errors or warnings.

## 2. Checks that need a person in a real window (REQUIREMENTS.md J2)

"User screenshot" means the project owner played a build and sent a screenshot. That is evidence for what the screenshot shows, not for the whole feature.

| Check | Status | Evidence / reason |
|---|---|---|
| Play loads the station with no errors | PASS | automated; also played by the project owner |
| Movement and look; no clipping | PASS (partly) | automated physics test; user screenshots show walking into all three rooms. Mouse-look feel not separately rated |
| `E` prompts within reach | NOT RUN (by me) | aiming selection is tested headless; the on-screen prompt text was not checked in a window |
| Each puzzle: correct repairs, wrong penalizes | PASS | automated; user screenshots show the valve panel, the tuner and `PRESSURE MISMATCH -10 s` / `NO SIGNAL -10 s` |
| Reboot terminal locked below 3/3, works at 3/3 | PASS | automated; user screenshot of the win screen (515 points) |
| Reserve reaches 0 → fail screen | PASS (automated only) | never seen in a window |
| `H`, `M`, `Esc` pause the reserve and restore control | PASS (automated only) | headless cannot test mouse capture itself |
| Mouse capture and release | NOT RUN | headless Godot ignores mouse capture (verified); needs a window |
| Hold-R retry feel and progress bar look | NOT RUN | logic tested; appearance not seen |
| Next Shift gives a new seed; menu round trip | PASS | automated; win screen with `SHIFT 02` seen |
| Three consecutive shifts, no leaked nodes | PASS | automated (see `test_menu_flow.gd`) |
| ORACLE offline fallback | PASS | automated, including the real client with the server down |
| ORACLE with a real local model (Ollama) | PASS (headless, 7 questions) | run on 2026-11-11 against the real qwen2.5:1.5b, answers in about 0.4-1.7 s once loaded. See section 2a. Not yet tried by the project owner in the game window |
| Main Menu, Manuals panel, ORACLE window, checklist: how they look | NOT RUN | built after the last user screenshots |
| Fog, wall display plates, reboot terminal colour change (M5 polish) | NOT RUN | added in M5; never viewed in a window |
| Mission briefing text and the PROTOCOL line in the checklist | PARTLY | the checklist line is visible in project-owner screenshots; the briefing text was seen on the How to Play page |
| Redesigned hub and rooms (header signs, door frames and lights, flanking boards, breaker labels, room panels, reboot sign, coach line, checklist) | PASS (reviewed in rendered screenshots) | rendered with `tools/screenshot.gd` on the development Mac (Metal, 1280x720) from 7 viewpoints, both unrepaired and repaired. Layout problems found this way and fixed: the coach line ran off both screen edges, the checklist crowded a door sign, and the reboot terminal had no label. The floor guide lines were removed after the project owner found them ugly. Not yet viewed by the project owner after the redesign |
| ORACLE hint button, run total on the win screen | NOT RUN | logic is tested; appearance not viewed in a window |
| Protocol A/B rules are fair and learnable in play | NOT RUN | logic and manuals are tested; whether players find it fun or too fiddly has not been playtested |
| Legible at 1280×720 | PASS (partly) | user screenshots are 1280×720 and text was readable after fixes; not re-checked for M3–M5 screens |
| Legible at 1920×1080 | PASS (layout only) | `test_layout.gd` checks that windows and buttons fit at 1920×1080; text legibility there was not viewed |
| Frame rate (30+ FPS target) | NOT RUN | not measured |
| Works with no internet | PASS (by design) | the only network call is to `127.0.0.1`; fallback tested with the server down |

### 2a. Real model (Ollama + qwen2.5:1.5b): what was observed

Real questions were sent through the real pipeline many times. Findings, in the order they happened:

1. **The raw model made mistakes.** It said "flip the 208-volt breaker" and "start with B4, then B3, B2, B1" (it cannot see the breakers, so these were invented), "flip to the highest available voltage" (wrong), and it gave only Protocol A when the manual gave both.
2. **Guards were added** (shown only the matching manual sentences; reject invented breaker names, voltages and numbers; require both protocols to be mentioned when both were shown). A project-owner screenshot from a game window started before these guards showed the model answering "the first breaker to flip is B1, the lowest voltage breaker" for protocol B restore mode: wrong, and invented.
3. **The guards were not enough.** A 21-question run with the guards in place still let through wrong answers: for "protocol B, restore mode, which breaker first?" the model said "flip from the lowest voltage to the highest" in 2 of 3 runs (the manual says highest first), and for "4 lit beacons on protocol B" it said 130 MHz (the correct value is 140). A guard cannot catch a reversed direction or a reused example number.
4. **Design change, tested:** questions about puzzle rules, orders and numbers are now answered exactly in code from the manual and the game's constants. The model is not used for them. If the player writes the breaker voltages they read plus the protocol and mode, the flip order is calculated; comms frequencies are calculated from the beacon count. The model is used only for general questions (scoring, what to do next, controls, retrying), still behind the guards.
5. **Result of a 21-question re-run after the change:** every rule question was answered exactly and correctly (for example protocol B, 4 beacons: 140 MHz; protocol B restore: highest first). General questions got sensible local answers.

Remaining weakness: the model's wording on general questions can still be slightly off. The exact manual text is shown under every answer. Not measured: first-answer delay on a cold start, and behavior on a slower computer.

## 3. Packaging

| Item | Status | Notes |
|---|---|---|
| Runs from source in the Godot editor (macOS) | PASS | opened and played by the project owner |
| `export_presets.cfg` for Windows Desktop | written, NOT verified | Godot loaded the preset by name |
| Windows `.exe` export | **NOT RUN** | the export failed before building because the export templates for 4.7.2 are not installed (`export_templates/` is empty). No `.exe` exists |
| Running on Windows | **NOT RUN** | no Windows machine available |
| Exported build can read `game_knowledge.json` | NOT RUN | the include filter `data/*.json` is set, but no export was produced to confirm it |

## 4. Known limitations

- A small local model can still word things badly or miss detail. The safeguards in 2a catch invented numbers, invented breakers and one-sided protocol answers, but not every wording problem; that is why the exact manual text is always shown next to the answer.
- Wall text fills the screen if the player stands right against a back wall.
- Scores are comparable only because every shift uses the same reserve; there is no difficulty scaling.
- The project was saved by Godot 4.7.2; opening it in an older Godot 4 version is untested.
- The puzzle values for one seed are random; the generator is deterministic only for the same (seed, attempt).
