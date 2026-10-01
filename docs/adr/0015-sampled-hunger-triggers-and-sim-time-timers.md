---
status: accepted
---

# Sampled hunger triggers replace per-decide eating rolls; gauge-affecting timers run in sim time

Moving to multi-hour rates (satiety decays 12.5/hr) broke ADR-0010's chance-based eating. `rollWantsToEat` fired on every FSM re-decide — every 2–4 *real* seconds, ~1000 rolls an hour — so even a 1% chance fired within minutes and a chicken hovered at whichever ceiling was in force instead of at the ~25 unfed floor the offline math depends on. Worse, because those FSM timers were real-time while gauges scale with the debug time scale, the outcome changed with time scale, which made the online/offline parity test meaningless.

We now sample the thresholds instead of rolling at them: whenever a hunger cycle ends, a chicken picks a food trigger (70–85), a forage trigger (10–20) and a forage stop (30–40). Crossing the trigger for the current mode (food placed or not) is detected inside the gauge update and flags the FSM, which interrupts idle/wander. With food it eats in deterministic bouts (half the gap to 100, all of it once the gap is ≤15) separated by 20–60 s breaks until it reaches 100; foraging eats to the forage stop. These ranges put the time-averaged satiety at ~90 fed and ~25 unfed, which are exactly the offline fed plateau and unfed floor. Every timer that can move a gauge (idle dwell, bout break, treat linger) runs on `Clock.after` in sim time; only walk tweens and animation stay real-time.

This supersedes ADR-0010. The problem ADR-0010 solved — a *fixed* enter/exit pair can't express a ceiling that changes with food availability — doesn't recur, because each mode has its own trigger and the mode switches the moment food appears or runs out.
