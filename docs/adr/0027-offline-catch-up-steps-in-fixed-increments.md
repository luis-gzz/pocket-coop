---
status: accepted
---

# Offline catch-up advances in fixed steps of pure arithmetic

ADR-0016 computed time away in closed-form phases and never stepped time. That held cleanliness at one average for the whole absence and ignored buffs and floor eggs, so it over-counted eggs for an away hen, and every new rule (the lay gates of ADR-0026 now; decline, appetite and chicks later) would have needed its own phase and break points.

`Offline.compute` now advances every chicken together in steps of five sim-minutes (`Tuning.OFFLINE_STEP`; 288 for the 24 h cap, with a shorter last step). Each step: food and water top hens up to their plateaus and hold them there while the shared pools last, else the gauges decay toward 0; droppings add to a running dirt total; cleanliness eases toward that dirt; then each hen lays under the same `Gauges.layRate` live play uses, taking an open bed slot if one is left and otherwise counting as a floor egg that adds dirt from then on. Happiness buffs and the satisfied spell count until their expiry timestamps. The minimum lay gap is enforced per egg, so the old `maxEggs` cap, the Simpson averaging and garden.lua's after-the-fact cleanliness easing are gone.

What ADR-0016 was really protecting still stands: offline is pure data in and out over the shared tuning table, with no display objects and no state machine, and it must land where watching would have. It still doesn't replay walking, bouts or positions; eating is still modelled by the fed and watered plateaus. Five minutes was chosen over one because halving the step doesn't move the egg count (checked by `tools/parity.lua`), and the cost either way is negligible.

Supersedes ADR-0016. Its amendment (the ten-minute threshold, the welcome-back card, treats never used while away) carries over unchanged.
