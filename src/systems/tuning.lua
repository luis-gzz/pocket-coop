-- Tuning shared by the online sim and offline catch-up (ADR-0016). Rates are
-- per sim-hour, converted to per-second here; seconds are sim-seconds.
local Tuning = {}

local HOUR = 3600
Tuning.HOUR = HOUR

-- Satiety.
Tuning.SATIETY_DECAY_PER_HOUR = 12.5 -- 100 -> 25 over 6 h
Tuning.SATIETY_DECAY_RATE = Tuning.SATIETY_DECAY_PER_HOUR / HOUR
Tuning.SATIETY_EAT_RATE = 100 / 300 -- per second of active eating
Tuning.SATISFIED_DURATION = 30 * 60 -- granted on reaching 100
Tuning.SATISFIED_DECAY_FACTOR = 0.25
Tuning.FORAGE_CEILING = 50
Tuning.FOOD_CEILING = 100

-- Hunger triggers (ADR-0015), resampled each time a hunger cycle ends.
Tuning.FOOD_TRIGGER = { min = 70, max = 85 }
Tuning.FORAGE_TRIGGER = { min = 10, max = 20 }
Tuning.FORAGE_STOP = { min = 30, max = 40 }
Tuning.BOUT_FINISH_GAP = 15 -- a gap this small eats straight to 100
Tuning.BOUT_BREAK = { min = 20, max = 60 } -- seconds between bouts

-- Food units: C satiety per unit, so 100 units hold one fed chicken for
-- about an hour.
Tuning.SATIETY_PER_UNIT = 0.1
Tuning.FED_UNITS_PER_CHICKEN_HOUR = 100

-- Where online eating settles - offline's fed value and unfed floor.
Tuning.FED_PLATEAU = 90
Tuning.UNFED_FLOOR = 25

-- Cleanliness eases toward its target with this time constant (closed
-- form, so it's exact for any dt - a short app switch or an offline gap).
Tuning.CLEAN_PENALTY_PER_DROPPING = 10
Tuning.CLEAN_PENALTY_PER_FLOOR_EGG = 5
Tuning.CLEAN_EASE_RATE = 1 / (30 * 60) -- per second: ~63% of the gap per 30 min

-- Hydration: 100 -> 0 over 4 h; a drink runs straight to 100.
Tuning.HYDRATION_DECAY_PER_HOUR = 25
Tuning.HYDRATION_DECAY_RATE = Tuning.HYDRATION_DECAY_PER_HOUR / HOUR
Tuning.HYDRATION_DRINK_RATE = 1.2 -- per second of drinking: ~30 s from a trigger
Tuning.THIRST_TRIGGER = { min = 55, max = 75 }
Tuning.BOWL_WATER = 16 * Tuning.HYDRATION_DECAY_PER_HOUR -- 16 chicken-hours
Tuning.WATERED_PLATEAU = 85 -- offline's watered value

-- Happiness: satiety/hydration at or above their knee count as full;
-- below DEHYDRATED_BELOW hydration scales happiness toward 0 (ADR-0019).
Tuning.HAPPINESS_SATIETY_KNEE = 85
Tuning.HAPPINESS_HYDRATION_KNEE = 80
Tuning.DEHYDRATED_BELOW = 10

-- Droppings.
Tuning.POOP_PER_HOUR = 0.5 -- one every ~2 h
Tuning.POOP_RATE = Tuning.POOP_PER_HOUR / HOUR

-- Egg laying.
Tuning.LAY_BASE_PER_HOUR = 1 / 4
Tuning.LAY_HAPPINESS_GATE = 33
Tuning.LAY_FULL_RATE_HAPPINESS = 85
Tuning.LAY_MIN_RATE_FACTOR = 0.25 -- fraction of base rate right at the gate
Tuning.LAY_MIN_GAP = HOUR

-- Progress thresholds (poop and lay) are jittered per event so online
-- doesn't feel clockwork; offline uses the average (1).
Tuning.THRESHOLD_JITTER = { min = 0.8, max = 1.2 }

-- Offline catch-up. Shorter absences than the threshold just run the
-- normal update path with one big dt instead of a full pass.
Tuning.OFFLINE_CAP = 24 * HOUR
Tuning.OFFLINE_THRESHOLD = 10 * 60

function Tuning.randomIn(range)
	return range.min + math.random() * (range.max - range.min)
end

return Tuning
