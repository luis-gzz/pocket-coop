# Coopful — Multi-Hour Simulation: Online Behavior + Offline Recalculation

## Goal

Move the game from a minutes-scale test loop to a **multi-hour real-time pet**, and add **offline recalculation** so the yard's state is correct when the player returns. Online and offline must tell the same story: offline is a shortcut that lands where watching would have landed, not a separate ruleset.

Everything here builds on systems already implemented (fullness/satiety, cleanliness with droppings + floor eggs, derived happiness, FSM, egg laying, beds, food supplies). Where an existing equation is only adjusted, this doc says what to change — it does not restate or replace the equation.

**Not in scope:** water/thirst, poop spot, breeding/hatching, coop screen, fox. None of these exist yet; offline should simply not account for them.

---

## Shared principles

1. **All rates are per real-time hour** and scale with the existing `time_scale` debug multiplier, so a multi-hour day can still be tested in minutes.
2. **One set of tuning constants** is read by both the online simulation and the offline recalculation. Offline never uses its own hand-picked numbers.
3. **Offline never steps through time.** It splits the absence into at most a few phases and uses closed-form arithmetic per phase.
4. **Fractional progress carries over.** Egg-laying and pooping each keep a stored progress value, so partial progress isn't lost between sessions (e.g., 0.6 of an egg before closing + 0.5 during the absence = one egg with 0.1 left over).

---

## Tuning table (starting values — expect to tune)

| Constant | Value | Notes |
|---|---|---|
| Fullness decay (normal) | 12.5 / hr | 100 → 25 over 6 h |
| Satisfied buff | 30 min after reaching 100 | decay × 0.25 (3.125 / hr); eat-want × 0.25 |
| Foraging ceiling | 50 | foraging can never raise fullness above 50 |
| Unfed equilibrium | ~25 | where foraging + decay settle; offline floor |
| Fed plateau | ~95 | where a well-fed chicken hovers; offline "fed" value |
| Happiness fullness plateau | 85 | fullness ≥ 85 counts as fully fed |
| Food coverage | 100 units = 1 chicken · 1 hour | defines average consumption |
| Poop average | 1 per chicken per hour | |
| Poop check interval (online) | 15 min | chance tuned to average ~60 min |
| Egg cadence | 1 per ~4 h at full happiness | |
| Lay happiness gate | 33 | no laying below |
| Minimum time between eggs | 1 h | per hen |
| Offline cap | 24 h | longer absences count as 24 h |

---

## 1. Fullness (satiety)

### Online

- **Decay:** fullness falls at the normal decay rate whenever the chicken isn't eating. During the **satisfied buff**, decay drops to 25% of normal.
- **Satisfied buff:** granted whenever fullness reaches 100. Lasts 30 minutes (stored as an expiry timestamp). While active: decay × 0.25, and the chicken's chance to *enter* eating is × 0.25. The buff **biases** eating but never blocks it — if fullness does drop meaningfully during the buff, the chicken can still eat.
- **This buff replaces the earlier "slow decay above 90" idea.** Don't implement both.

### Online eating bouts (placed food)

When the FSM enters Eat and placed food is available, the chicken walks to the nearest food and eats in **bouts**:

- A bout eats **half the remaining gap to 100** (e.g., 60 → 80, 80 → 90).
- If the remaining gap is **15 or less**, the bout eats all the way to 100 (avoids the never-quite-full problem) and triggers the satisfied buff.
- Between bouts the chicken takes a **short** wander/idle break (roughly 20–60 s) before deciding whether to eat again.
- Keep the existing fullness-weighted eat-entry probability; just apply the satisfied-buff multiplier on top.

### Online foraging (no placed food)

- When no placed food exists and fullness is **below 50**, the chicken can forage (an Eat behavior with no food object).
- Foraging raises fullness but **never above 50**.
- Tune forage gain and forage frequency so an unfed chicken's sawtooth averages **~25**. Verify with `time_scale`: leave a chicken unfed for ~6 simulated hours and confirm it hovers around 25. The offline floor below depends on this being true.

### Food supply ↔ fullness conversion

- Food stays a **depleting supply** (units drain only when eaten, nearest pile first online).
- Each unit eaten converts to a fixed amount of fullness (**C** fullness per unit). Food consumed = fullness gained ÷ C.
- **Choose C so that 100 units keep one fed chicken above 90 for about an hour.** Because a fed chicken's average loss is roughly 9–10 fullness per hour (mix of normal decay and buffed decay), the starting value is **C ≈ 0.09–0.1**. Tune by placing 100 units next to a full chicken and confirming it lasts ~1 hour with fullness staying above 90.
- ⚠️ Consequence of this definition: refilling a hungry chicken is expensive. Going from 25 → 95 costs ~70 ÷ C ≈ 700+ units. This is intentional (see the design decision at the end).

### Treats (instant fullness)

- Each treat type defines its own **instant fullness amount** as a per-item property. Don't hardcode a single value; future treats will differ.
- The **mealworm** is currently the only treat: **+25 instant fullness**. It keeps its existing happiness buff; its food effect is now instant fullness instead of an hour of food supply.
- A treat's fullness is applied immediately to the chicken that eats it, capped at 100. It does not go through the food-supply unit conversion.
- If a treat takes fullness to 100, it grants the satisfied buff like any meal.
- Treats are the fast way to recover a hungry chicken, since refilling from seed is deliberately slow and expensive (see the design decision at the end).
- Offline: treats are consumed while the player is watching, so they don't enter the offline calculation. A treat still sitting uneaten when the app closes should be eaten first on return, applying its fullness amount before the refill phase.

### Offline

Given `f0` (fullness at close), total food units `U`, chicken count `N`, and capped elapsed hours `T`:

1. **Refill phase.** Units needed to reach the fed plateau: `refill_units = max(0, 95 − f0) ÷ C`.
   - If `U < refill_units`: fullness becomes `f0 + U × C`, all food is consumed, and the rest of the absence is the starved phase starting from that value.
   - Otherwise spend `refill_units`; fullness is at the plateau. Treat refill as happening at the start of the absence.
2. **Fed phase.** Remaining units cover `fed_hours = min(T, remaining_units ÷ (100 × N))`. Fullness holds at the plateau. Units consumed = `fed_hours × 100 × N`.
3. **Starved phase.** `starved_hours = T − fed_hours` (minus refill time, treated as zero). Fullness decays from its phase-start value at 12.5 / hr and **stops at 25**: `max(25, start − 12.5 × starved_hours)`. If fullness was already below 25, it rises to 25 (foraging).
4. **Drain food objects** by the total consumed, oldest pile first (offline has no positions). Remove piles that reach 0.

The satisfied buff is ignored offline — a 30-minute effect is noise over a multi-hour absence. Just let its expiry pass.

---

## 2. Cleanliness

### Online

- **Poop check every 15 minutes** (up from 60 s). Retune the base chance and the recently-ate / overdue bonuses so a fed chicken averages **one dropping per hour**.
- **Store poop progress** (fraction toward the next dropping) so offline can carry it — see below. Online can keep the chance roll; offline uses the average.
- The existing cleanliness model (easing toward a target set by the count of dirty items — droppings + floor eggs) is unchanged. No edits to that equation.

### Offline

- Expected droppings: `poop_progress + T × 1 × N`. Spawn the whole-number part; store the remainder as the new poop progress.
- Offline droppings go at **random positions within the world rect** (offline doesn't know where chickens were). Give them timestamps spread across the absence.
- **Cleanliness at return = the existing target for the dirty-item count at return** (droppings + floor eggs). Over a multi-hour absence the ease-toward-target has fully converged, so no easing math is needed.

---

## 3. Happiness

- **Update the existing happiness calculation so the fullness input reaches its maximum at fullness 85** and stays there above it. Scale smoothly up to 85; don't make it a snap/step. No other change to the formula.
- Effect: a well-fed chicken hovering in the 85–100 band reads as fully content, and the fullness sawtooth doesn't make mood jitter.
- Offline: happiness is still derived — nothing to store. Section 4 computes phase happiness values for egg laying from the phase fullness and cleanliness.

---

## 4. Egg laying

### Model change: rate accumulator (online and offline)

Replace the per-minute chance roll with a **lay-progress accumulator** per hen, so online and offline share one mechanism:

- `lay_rate(h)` = eggs per hour at happiness `h`:
  - `h < 33` → 0
  - `33 ≤ h < 85` → ramps from 25% to 100% of the base rate
  - `h ≥ 85` → base rate = **1 egg / 4 h**
- Online: each update, `lay_progress += lay_rate(happiness) × dt`. When progress reaches the hen's next threshold, she lays, progress resets, and the minimum 1-hour gap starts.
- To keep online from feeling clockwork, randomize each hen's next threshold between **0.8 and 1.2** when she lays. Store that threshold with the hen.
- Placement priority is unchanged: nearest open bed → near the closest bed → random position.
- Save on lay (already implemented) now also saves lay progress and the next threshold.

### Offline (two-phase)

Using the same phases computed for fullness:

- **Fed-phase happiness:** derived from fullness 95 and cleanliness averaged across the absence (average of the target at close and the target at return).
- **Starved-phase happiness:** derived from the midpoint fullness of the starved decay (or 25 if the starved phase ran past ~6 h) and the same cleanliness average.
- `eggs = lay_progress + fed_hours × lay_rate(h_fed) + starved_hours × lay_rate(h_starved)`.
- Cap by the minimum gap: no more than `T ÷ 1 h` eggs per hen.
- Lay each whole egg with the normal placement rules (beds first, in the order they would have filled). Store the remainder as lay progress.
- Floor eggs laid during the absence count as dirty items at return (they're included in the cleanliness target). The within-absence effect of floor eggs suppressing later laying is **ignored** offline — an accepted approximation.

---

## 5. Offline recalculation — order of operations

Run once on launch and on every return to foreground:

1. `elapsed = now − last_update`. If negative (clock moved backwards), treat as 0. Cap at **24 h**.
2. Expire timestamp buffs (pet, satisfied) against `now`. Their effects are not integrated offline.
3. **Fullness + food** — refill / fed / starved phases (Section 1). Record `fed_hours` and `starved_hours`.
4. **Droppings** — spawn expected count (Section 2).
5. **Eggs** — two-phase lay count, then placement (Section 4). Uses the cleanliness average, so it runs after droppings are known.
6. **Cleanliness** — set to the target for the final dirty-item count.
7. Happiness derives from the results automatically.
8. Set `last_update = now` and **save immediately**.

After this, the online simulation continues from the computed state.

---

## 6. Saving requirements for offline

Offline recalculation only works if state is saved when the app leaves the foreground:

- **Save on suspend/background and on exit**, including `last_update`.
- Existing immediate saves (lay, collect, place) stay.
- A light periodic save during long online sessions (e.g., every few minutes) protects against crashes.
- Saved state must include: fullness, cleanliness, satisfied-buff expiry, pet-buff expiry, each hen's lay progress + next threshold + last-lay time, poop progress, all food piles (units remaining, placed time), droppings, eggs, beds, coin count, `last_update`.

---

## 7. Testing

- With `time_scale` set high, verify the online anchors:
  - An unfed chicken settles around 25.
  - 100 units keep a fed chicken above 90 for ~1 hour.
  - A fed chicken poops ~once per hour.
  - A happy hen lays ~once per 4 hours.
- **Parity test:** run the same scenario two ways — once watched online at high `time_scale`, once closed and recalculated offline for the same span. Fullness, food remaining, egg count and dropping count should roughly match. Big gaps mean online tuning and the offline constants have drifted.
- Test the absences that exercise each branch: food outlasts absence; food runs out mid-absence; no food at all; absence past 24 h; clock set backwards.

---

## Design decision: refill is expensive on purpose

Defining "100 units = one chicken for one hour" while staying above 90 makes food cheap to *maintain* a full chicken but expensive to *refill* a hungry one (25 → 95 ≈ 700 units ≈ 7 seed spreads at C ≈ 0.1). **This is intentional:** neglect is costly to undo, which rewards keeping food out. Treats (Section 1) are the fast recovery path.
