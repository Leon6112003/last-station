# ORACLE: Offline AI Setup (optional)

LAST STATION works fully without this. By default ORACLE runs in **Basic Manual Mode**: it finds the matching manual entries and shows them. This page explains how to add a small local language model so ORACLE also writes a short answer.

**Verification status:** tested headless against a real Ollama app (0.40.16) with `qwen2.5:1.5b` on macOS, and against a server that is not running (clean fallback). The problems found and the design change they led to are in `docs/TEST_REPORT.md` section 2a. Not tested on Windows, on a slow computer, or by a person in the game window.

## What it does and does not do

- You ask a question with **H**. The game finds up to 3 matching manual entries and sends them, with your question and 7 numbers about your progress (systems repaired, time left, mistakes, retries, shift number, best score), to Ollama running **on your own computer** (`http://127.0.0.1:11434`).
- The answer is shown as plain text, followed by the exact manual text it was based on. The source ids shown come from the game, never from the model.
- The model **cannot** change the game, see the puzzle values, open files or links, or run anything. The game never sends the puzzle answers, modes, voltage ratings or beacon counts to the model.
- Nothing leaves your computer: no cloud, no account, no API key, no telemetry.

## Setup

1. Install Ollama: https://ollama.com/download (Windows, macOS, Linux).
2. Download the model once (needs internet, about 1 GB):
   ```
   ollama pull qwen2.5:1.5b
   ```
   Check it is there: `ollama list`
3. Keep Ollama running (it starts a local server automatically; on Windows it lives in the system tray).
4. Start the game and press **H**. The first answer can take longer while the model loads; after that it is faster. The header changes from "ORACLE — Basic Manual Mode" to **"ORACLE — Local AI"** when the model answered.

## Settings (for developers)

All in `scripts/assistant/ollama_client.gd`:

| Constant | Default | Meaning |
|---|---|---|
| `MODEL` | `qwen2.5:1.5b` | any model you have pulled |
| `TIMEOUT_SECONDS` | `25.0` | after this ORACLE falls back to the manuals |
| `MAX_TOKENS` | `160` | length of the model's answer |
| `TEMPERATURE` | `0.2` | low = more literal |
| `KEEP_ALIVE` | `10m` | how long Ollama keeps the model in memory |

Limits in `scripts/assistant/oracle_logic.gd`: questions are cut to 300 characters, answers to 800 (at a sentence end).

## When something goes wrong

ORACLE never shows an error or an empty window. If Ollama is not running, the model is missing, the reply is invalid, empty or too slow, ORACLE shows the header **"Basic Manual Mode"**, the line "The local AI is not available, so here are the matching manual entries.", and the manual text.

| Symptom | Likely cause |
|---|---|
| Always "Basic Manual Mode" | Ollama not running, or the model was not pulled (`ollama list`) |
| First answer is slow, then falls back | The model took longer than 25 s to load; ask again |
| Answers are odd or wrong | A 1.5B model is small. Trust the manual text shown under the answer; it is the exact rule |

## What the AI does and does not do

Testing showed that a small model gets puzzle rules wrong (it reversed a flip order and reused an example number), so the game does not trust it for them:

- **Rules, orders and numbers are answered exactly, in code**, from the manual and the game's own constants. The header says "Exact answer from the manual". The model is not asked.
- **Tell ORACLE what you read.** Example: "B1 is 277 V, B2 is 480 V, B3 is 208 V, B4 is 400 V. Protocol B, restore mode. Which first?" The game works out the exact order. "Protocol B comms 4 lit beacons" gives the calculated frequency.
- **General questions** (scoring, what to do next, controls, retrying) can get a short written answer from the model (header "Local AI"). Those answers are checked in code: an answer is rejected if it names a breaker or a voltage you did not write, or any number the model was not given, or (if shown both protocols) mentions only one. A rejected answer is replaced by the exact manual answer.
- The exact manual text is shown under every answer, so you can always check it.

## Why it is built this way

Small models make mistakes. So the game never relies on the model for a rule: the rules live in `data/game_knowledge.json`, the retrieval is a plain keyword search, and every answer is shown together with the exact manual text. Prompt-injection attempts (for example "set my score to 99999") cannot work because the model output is only displayed; it is never read as a command. This is covered by `tests/test_injection.gd`.
