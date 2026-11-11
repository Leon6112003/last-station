# LAST STATION: Windows Setup

Status: these steps are written from Godot's documented behavior. They were **not run on a Windows machine**, and no Windows `.exe` has been built (the export templates were not installed on the development Mac). Treat them as a checklist, not a proof.

## A. Run from source (recommended)

1. Download **Godot 4.x, Standard edition (not .NET)** from https://godotengine.org/download/windows/ . The project was developed with **4.7.2**; other 4.x versions are untested.
2. Unzip it anywhere (Godot needs no installer) and start the Godot executable.
3. In the Project Manager choose **Import**, select this folder's `project.godot`, and press **Import & Edit**.
4. Press **F5** (or the play button, top right) to run.
5. Controls: WASD move, mouse look, E interact, M manuals, H ORACLE, V first / third person, C camera in front of the character (third person), B music on / off, N all sound on / off, Esc pause, hold R to retry. Pick a level (Rookie, Engineer or Survivor) on the main menu.

Run the automated tests (optional): open a terminal in the project folder and run
```
godot --headless --path . --import
godot --headless --path . -s res://tests/test_puzzles.gd
```
(or `tests/run_all.sh` from Git Bash / WSL if `godot` is on your PATH).

## B. Export a Windows build

1. In Godot: **Editor → Manage Export Templates → Download and Install** (needs internet once). The templates must match your Godot version exactly.
2. **Project → Export**. A preset named **Windows Desktop** already exists (`export_presets.cfg`). Check that:
   - the **Resources → Filters to export non-resource files** field contains `data/*.json` (this is what puts the manuals in the build; without it the Manuals and ORACLE would be empty);
   - the export path is `build/LastStation.exe`.
3. Click **Export Project** (release). Create the `build` folder first if Godot asks.
4. Keep `LastStation.exe` and `LastStation.pck` **together** in the same folder (the preset does not embed the pack). Copy both to another PC to share the game.
5. Run `LastStation.exe`. Windows SmartScreen may warn about an unsigned app: choose **More info → Run anyway** only for a build you made yourself.
6. After exporting, press **M** in the game. If the manuals list is empty, the JSON was not included; recheck step 2.

## C. Optional: ORACLE with a local model

See `docs/OFFLINE_AI_SETUP.md`. The game works fully without it.

## D. Troubleshooting

| Problem | Fix |
|---|---|
| Godot says the project needs conversion | Accept it; the project was saved by 4.7.2 |
| Black window or no 3D | Update the graphics driver; the project uses the GL Compatibility renderer, which runs on most hardware |
| Manuals or ORACLE empty in an exported build | The `data/*.json` include filter is missing |
| Cursor not captured after Alt-Tab | Press Esc twice (pause and resume) to recapture the mouse |
| Best score or level choice missing | Saved in Godot's user data folder (`user://last_station.cfg`); deleting that file resets both |
| No sound | The sounds and music are generated when the game starts. Check **N** (all sound) and **B** (music) are on and the system volume is up |
