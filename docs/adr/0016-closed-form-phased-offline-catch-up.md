---
status: accepted
---

# Offline catch-up is closed-form and phased, not a replay of the update loop

ADR-0003 anticipated catching up for time away by calling the same gauge update path with one large dt. That can't work once behaviour depends on the FSM (hunger cycles, bouts, walking to food, nesting) and on discrete events (droppings, eggs, food piles emptying), and stepping a day in small increments on every launch is wasteful and still wouldn't reproduce positions.

Instead `src/systems/offline.lua` splits the absence (capped at 24 h, floored at 0 if the clock moved back) into at most three phases — refill to the fed plateau, fed while food lasts, starved decaying to the unfed floor — and uses arithmetic per phase: food drained oldest-pile-first, droppings and eggs from the same fractional progress accumulators the online gauges use, egg rates from two-phase happiness. Parity is kept by construction rather than by shared code paths: both sides read one constants table (`src/systems/tuning.lua`), and the online tuning is chosen so its time-averages *are* those constants (ADR-0015). Offline deliberately ignores short-lived effects (satisfied/happiness buffs, floor eggs suppressing later laying) and places droppings and no-bed eggs at random, since it has no positions. A drift between online behaviour and these constants is caught by the parity test (watch N hours at high time scale vs. the debug "+Nh" skip), not prevented structurally.

This supersedes ADR-0003's "no offline reconstruction" and "large-dt replay" parts; its plain-JSON persistence choice still stands, now with a wall-clock `lastUpdate` stamped on every save.
