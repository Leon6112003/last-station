# LAST STATION: demo script (about 5 minutes)

A route that shows the whole project without depending on luck. Start from the main menu.

## Before you start
- Close other apps, set the game to full screen if you like (the interface scales).
- Pick **Rookie** (more time) and switch no modifiers on.
- Keep `README.md` and `docs/TEST_REPORT.md` open to answer questions.

## The route
1. **Menu (20 s).** Point out the three levels and three optional modifiers, and the Settings button. "It is a short survival puzzle: the station is failing and I have limited oxygen."
2. **Wake up and walk (30 s).** Press Play. You wake in bed, walk out, and the guidance line tells you where to go. "Only the first shift wakes you in bed."
3. **Read the rule, do not guess (60 s).** In the Power room read the LOAD MODE and the breaker voltages. Press **H** and ask ORACLE which breaker first. Show that the answer is the manual text shown verbatim, with its source. "The rules live in written manuals. ORACLE finds the right page by keyword and quotes it; for rules and numbers it answers in code, never from the AI."
4. **Repair it (20 s).** Flip the breakers. The cross beside POWER becomes a tick, the door light turns cyan and the next door unlocks.
5. **A hazard (40 s).** Walk the corridor: show a gas vent (the lamp and the word SAFE / SOON / DANGER), then the Oxygen room's leak at the console. Fix Oxygen: the leak and a corridor vent are sealed and a notice says so. "Repairs switch off the hazards they were feeding."
6. **The zero-gravity zone (20 s).** Float in for a second to show the reserve draining, then use a wall switch and walk through. "Repairing Comms later restores gravity here for good."
7. **Jump ahead (30 s, optional).** Pause (Esc), show **Settings**: the volume sliders, rebinding a key and the accessibility options. Press N to mute and show the sound captions appear.
8. **The finale (60 s).** With all four systems repaired (use whichever you finished; or start the demo with `--shift=3` and repair quickly), walk to the reboot terminal. The **reboot code** flashes four pads: repeat them in the same order (protocol A) or reversed (B). Ask ORACLE how. Make one wrong pad on purpose to show the penalty and the replay.
9. **Results and adaptation (30 s).** The win screen starts with **ADAPTIVE DIFFICULTY**: the decision (harder, easier or balanced), the numbers behind it and a plain sentence, then the score and the next shift's reserve. "After every shift the game adapts the next one with a fixed rule, not machine learning. A quick clean clear makes it harder; a struggle makes it gentler."

## What to say about the design (30 s)
- **Rule-based, not machine learning.** Difficulty, hazards and ORACLE's retrieval are plain code and keyword scoring. Say this plainly.
- **Offline.** No accounts, analytics or online services. The optional local model runs on your own computer.
- **The AI cannot change the game.** ORACLE only displays text; the security boundary is in code and is tested with injection strings.
- **Tested.** 30 test files and 1263 automated checks; the test report says what was and was not verified, including that no Windows build exists.

## If something goes wrong
- A window does not open or controls stop working: press Esc twice (pause and resume) to recapture the mouse.
- A shift is lost: hold R to retry the same station with new puzzle values.
- The local model is not installed: say so, and show **Basic Manual Mode**, which needs no setup.

## Questions you may get
- *Why does the protocol matter?* It changes the Power order, the Oxygen table, the Comms and Cooling formulas and the reboot code, so a rule learned once is not enough: you have to check it each shift.
- *Can ORACLE give me the answer?* It gives the rule and, when you tell it what you read, the calculation. It never sees the puzzle values.
- *What is not finished?* A Windows build and performance on weaker hardware (see `docs/HANDOFF.md`).
