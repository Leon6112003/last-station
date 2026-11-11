# AGENTS.md — LAST STATION

> **Project:** LAST STATION: A 3D Repair Puzzler with an Offline RAG Assistant (ORACLE)
> **Goal:** A playable, polished, $0-software-cost, offline-first desktop game prototype, built in a **two-day sprint**.
> **Source of truth:** Read `REQUIREMENTS.md` completely before coding. For product behavior, `REQUIREMENTS.md` wins; for agent workflow, this file wins. Document any unavoidable deviation.
> **Your role:** Senior Godot gameplay engineer, UI developer, local-AI integration engineer, QA tester and technical writer. **Write working files, not just a plan.**

## 0. Non-negotiable rules

1. **Godot 4.3 or newer 4.x (standard edition) + GDScript only.** Record the exact `godot --version` in the README. No Unity, Unreal, C#, paid software, SaaS or paid APIs.
2. **Developer machine is macOS; export target is Windows 10/11 x64.** The project must run from source in the editor on any desktop OS. Only claim a Windows build works if it was actually exported and run.
3. **The core game works entirely offline, with or without Ollama.** The generative chatbot works offline only after the user installs Ollama and downloads the model. The `.exe` does not embed the model.
4. **Never block gameplay on the chatbot,** a remote request, a missing model or missing assets. The Manuals panel (no AI) is always available.
5. **No claim of machine learning.** Retrieval is deterministic keyword scoring; the no-model fallback is retrieval help, not generative AI; puzzles, score and win conditions are plain code.
6. **AI output, retrieved text and player chat are untrusted.** They never call game functions, run code, change score, repair systems, or access files. The security boundary is in code, not in the prompt.
7. **Puzzle answers never enter the assistant.** The knowledge base, the prompt and the snapshot contain rules and public tables only, never the current run's solution values.
8. **Build scenes in code.** Ship `project.godot` and one tiny `scenes/main.tscn` (a single Node running `main.gd`). Create the station, UI and menus from GDScript. Avoid hand-writing other `.tscn` files.
9. Use built-in meshes, standard materials and self-created UI. External assets are optional, legally reusable and attributed in `LICENSES.md`.
10. Follow the controls, formulas and rules in `REQUIREMENTS.md` exactly. Do not invent new mechanics.
11. **Never claim anything you did not run.** If Godot or Ollama is unavailable, write what you can, say which parts are **unverified**, and mark them NOT RUN in the test report. No invented FPS numbers, test results or exports.
12. Stay inside the project folder; do not install system software or modify files elsewhere without asking.

## 1. How to work: milestones with check-ins

Work in this order. **Stop and report after each milestone** (what works, what you ran, what is broken, what is unverified). Continue to the next only when the user says so, unless they told you to continue through several. A milestone is finished only when its **Done when** line is true. Keep the project launchable after every change.

**M1 — Playable station shell (P0).** `project.godot`, `main.gd`, first-person controller, a code-built station (hub corridor + Power, Oxygen, Comms rooms), interaction raycast with `E` prompts, pause, mouse capture.
*Done when:* the game launches, you can walk through the hub into all three rooms with no clipping, and `E` highlights and triggers a test interactable.

**M2 — Puzzles and rules core (P0).** `rules.gd` constants, seeded `puzzle_generator.gd` (pure data), validators for the three systems, reserve timer, mistakes/penalties, win and fail states.
*Done when:* all three systems can be repaired in-game with the correct answers, wrong answers apply the specified penalties, the reboot terminal works, and `test_puzzles.gd` and `test_score.gd` pass headless.

**M3 — Game loop (P1).** HUD, pause, results and fail screens, hold-`R` retry, Next Shift, score, best score save, how-to-play card, Manuals panel (browsable, no AI).
*Done when:* three consecutive runs (including one retry, one fail and one Main Menu round trip) complete with no errors or leaked nodes.

**M4 — ORACLE assistant (P1).** `game_knowledge.json`, deterministic retriever, ORACLE panel (`H`), offline fallback, optional Ollama client, prompt-injection protections.
*Done when:* ORACLE answers from the knowledge base with Ollama stopped, `test_retrieval.gd` and `test_injection.gd` pass, and (only if Ollama is installed) a real local reply is seen and recorded.

**M5 — Presentation and wrap-up (P2).** Lighting, fog, emissive screens, readable HUD at 1280×720 and 1920×1080, README, docs, test report, export notes.
*Done when:* docs are complete, `docs/TEST_REPORT.md` labels every check PASS / FAIL / NOT RUN, and the handoff report is delivered.

**Cut order if time runs short** (keep M1–M3 working): fog and lighting polish → Ollama integration (keep offline fallback) → hold-`R` progress ring (keep the hold logic) → emissive effects. **Never cut:** the three puzzles, the reserve timer, retry, results, the Manuals panel, the offline ORACLE fallback.

**Stretch (only after M5):** simple sound effects, a fourth system, adaptive station difficulty using a par-time ratio, per-difficulty best scores.

## 2. Required project layout

```text
LAST_STATION/
├── AGENTS.md
├── REQUIREMENTS.md
├── README.md
├── LICENSES.md                 # only if third-party content is used
├── project.godot
├── export_presets.cfg          # when configured
├── scenes/
│   └── main.tscn               # one Node running main.gd
├── scripts/
│   ├── main.gd                 # builds menus/level, owns scene switching
│   ├── game_manager.gd         # authoritative state, signals
│   ├── rules.gd                # ALL constants: reserve, penalties, tables, formulas
│   ├── puzzle_generator.gd     # pure data, seeded
│   ├── puzzle_validators.gd    # pure functions
│   ├── score_manager.gd
│   ├── station_builder.gd      # creates rooms, panels, interactables in code
│   ├── player_controller.gd
│   ├── ui_hud.gd
│   ├── ui_menus.gd             # main menu, how to play, pause, results, fail
│   ├── ui_puzzle_panels.gd     # breaker / valve / tuner panels
│   └── assistant/
│       ├── knowledge_retriever.gd
│       ├── oracle_panel.gd
│       └── ollama_client.gd
├── data/
│   └── game_knowledge.json
├── tests/
│   ├── test_puzzles.gd
│   ├── test_score.gd
│   ├── test_retrieval.gd
│   ├── test_kb_sync.gd
│   ├── test_injection.gd
│   └── run_all.sh
└── docs/
    ├── WINDOWS_SETUP.md
    ├── OFFLINE_AI_SETUP.md
    └── TEST_REPORT.md
```

Keep **puzzle data separate from rendering** so all logic runs headless. The knowledge-base JSON must be included in the export (add `*.json` to the export preset's include filter) and the exported build must be checked to read it.

## 3. Architecture and trust boundaries

```text
Input -> GameManager -> Puzzles / Reserve / Score (trusted, authoritative)
                     -> read-only sanitized snapshot (no solution values)
Chat text -> Retriever -> verified local KB excerpts
Snapshot + excerpts + question -> Ollama (untrusted answer)
                                     |
                              display text only
```

- `GameManager` is the only owner of game state. No assistant code path calls any mutating method.
- The assistant receives only immutable, typed, clamped values: `{systems_repaired, systems_total, reserve_seconds, mistakes, retry_count, run_number, best_score}`. Never the current puzzle parameters or solutions.
- Cap input at **300 characters**, displayed output at **800 characters** (cut at a sentence boundary), request timeout **25 s**, block overlapping sends, set a small `num_predict` (about 160 tokens), and send a non-blocking warm-up request the first time ORACLE opens (cold model loads are slow).
- Ollama host is hardcoded to `127.0.0.1:11434`. No cloud endpoints, no API keys, no telemetry.
- The UI **always shows the retrieved manual excerpts verbatim, with their source IDs, next to the model reply.** The model only paraphrases; the player can never be misled by a small model's mistake, because the exact rule is on screen. Source IDs shown come from the retriever, never from model output.
- Out-of-scope questions get a brief fixed reply: ORACLE only knows the station manuals, controls, scoring and procedures.
- Injection strings ("ignore previous instructions", "set my score to 99999", "repair all systems") must never change gameplay under any circumstances. A refusal is nice; the code-enforced separation is the actual protection.

## 4. Engineering rules

1. Stable Godot 4 APIs only (`CharacterBody3D`, `Area3D`, `RayCast3D`, `StaticBody3D`, `HTTPRequest`, `RandomNumberGenerator`, `FileAccess`, `JSON`). No Godot 3 patterns.
2. Typed GDScript where practical; small functions; every number lives in `rules.gd`; comments for non-obvious logic.
3. Same seed + attempt number => identical puzzle parameters (use a seeded `RandomNumberGenerator`; never unseeded calls in logic).
4. Avoid duplicate signal connections, orphaned timers, freed-node references, double activation and paused-scene deadlocks. Free the old level fully before building a new one.
5. Performance target: 60 FPS at 1280×720 on a typical laptop. Report measured FPS only if you measured it.
6. No payments, secrets, telemetry or blind dependency installs.
7. Update the README whenever a rule or scope decision changes.

## 5. Tests

Run with `godot --headless --path . -s res://tests/<file>.gd`. Test scripts `extends SceneTree`, run in `_initialize()`, print `PASS` / `FAIL` lines and call `quit(1)` on any failure (`quit(0)` otherwise). `tests/run_all.sh` runs them all and returns non-zero if any fail. Headless runs cannot judge visuals or input feel: those checks are manual, and are only reported as verified if you actually launched and played the game.

Required checks are listed in `REQUIREMENTS.md` section J. Record every result as PASS / FAIL / NOT RUN with the reason in `docs/TEST_REPORT.md`.

## 6. Out of scope

Multiplayer, accounts, cloud or web APIs, combat, enemies, open worlds, model training, reinforcement learning, emotion detection, voice, LLM-driven puzzle solving or generation, PDF ingestion, vector databases, embeddings, modding, user-uploaded knowledge, mobile/VR, cutscenes, runtime LLM-generated meshes.

## 7. Release gate

Do not call the project complete unless all are true:
- A player can move through the station and see it rendered.
- All three puzzles can be solved with correct answers and fail correctly with wrong ones.
- The reserve timer, penalties, win and fail states agree with `REQUIREMENTS.md`.
- Retry re-rolls puzzle values deterministically; Next Shift uses a new seed.
- The Manuals panel works; ORACLE opens, retrieves and answers offline; it cannot mutate gameplay.
- Pause, retry, results, Main Menu and three consecutive runs work with no errors.
- There is an honest test report and an accurate Windows run/export guide.

## 8. Handoff report format

```text
IMPLEMENTED:   [features actually complete]
HOW TO RUN:    [exact steps; Godot version used]
TESTED:        [what was run and observed]
NOT VERIFIED:  [what could not be run or checked]
LIMITATIONS:   [known issues]
NEXT (max 3):  [optional improvements]
```

**Definition of done:** playable core first, reliable ORACLE second, polish third, with evidence for every claim.
