local Tuning = require("src.systems.tuning")
local Gauges = require("src.objects.chicken.gauges")

-- Offline catch-up math (ADR-0027): the whole garden advanced in fixed
-- steps. Pure data in and out; garden.lua applies the result.
local Offline = {}

-- Shares `pool` out lowest gauge first, raising each chicken's `key` up to
-- `plateau` at `perPoint` pool per gauge point. Returns what's left.
local function refill(chickens, key, pool, plateau, perPoint)
	local order = {}
	for i = 1, #chickens do
		order[i] = i
	end
	table.sort(order, function(a, b)
		return chickens[a][key] < chickens[b][key]
	end)
	for _, i in ipairs(order) do
		local chicken = chickens[i]
		local points = math.min(math.max(0, plateau - chicken[key]), pool / perPoint)
		chicken[key] = chicken[key] + points
		pool = pool - points * perPoint
	end
	return pool
end

-- One step of a gauge that holds at `plateau` while the pool pays `upkeep`,
-- then decays by `decay` (both for the whole step). Returns the value and
-- what's left of the pool.
local function holdOrDecay(value, pool, plateau, upkeep, decay)
	local held = (upkeep > 0) and math.min(1, pool / upkeep) or 0
	pool = pool - held * upkeep
	if pool < 1e-9 then
		pool = 0 -- so rounding can't leave a crumb
	end
	if held > 0 then
		value = math.max(plateau, value - decay * held)
	end
	return math.max(0, value - decay * (1 - held)), pool
end

-- input: { units, water, dirt, openSlots, chickens = { { now, satiety,
-- hydration, cleanliness, satisfiedUntil, happinessBuffExpiresAt,
-- petBuffExpiresAt, lastLayAt, poop/lay progress + thresholds } } }.
-- Returns hours, unitsConsumed, waterConsumed and per-chicken results.
function Offline.compute(input, elapsedSeconds)
	local seconds = math.max(0, math.min(elapsedSeconds, Tuning.OFFLINE_CAP))
	local units, water = input.units or 0, input.water or 0
	local dirt = input.dirt or 0
	local openSlots = input.openSlots or 0

	local chickens = {}
	for i, source in ipairs(input.chickens) do
		local chicken = { droppings = 0, eggs = 0 }
		for key, value in pairs(source) do
			chicken[key] = value
		end
		chicken.now = chicken.now or 0
		chicken.cleanliness = chicken.cleanliness or Gauges.cleanlinessTarget(dirt)
		chicken.satisfiedUntil = chicken.satisfiedUntil or 0
		chicken.happinessBuffExpiresAt = chicken.happinessBuffExpiresAt or 0
		chicken.petBuffExpiresAt = chicken.petBuffExpiresAt or 0
		chicken.lastLayAt = chicken.lastLayAt or -math.huge
		chickens[i] = chicken
	end

	local remaining = seconds
	while remaining > 0 do
		local dt = math.min(Tuning.OFFLINE_STEP, remaining)
		remaining = remaining - dt
		local stepHours = dt / Tuning.HOUR

		-- 1-2. Food and water: top up to the plateau, hold there while the
		-- pool lasts, else decay toward 0.
		units = refill(chickens, "satiety", units, Tuning.FED_PLATEAU, 1 / Tuning.SATIETY_PER_UNIT)
		water = refill(chickens, "hydration", water, Tuning.WATERED_PLATEAU, 1)
		for _, chicken in ipairs(chickens) do
			local decay = Tuning.SATIETY_DECAY_PER_HOUR * stepHours
			if chicken.now < chicken.satisfiedUntil then
				decay = decay * Tuning.SATISFIED_DECAY_FACTOR
			end
			chicken.satiety, units = holdOrDecay(
				chicken.satiety, units, Tuning.FED_PLATEAU, Tuning.FED_UNITS_PER_CHICKEN_HOUR * stepHours, decay
			)
			local drying = Tuning.HYDRATION_DECAY_PER_HOUR * stepHours
			chicken.hydration, water = holdOrDecay(chicken.hydration, water, Tuning.WATERED_PLATEAU, drying, drying)
		end

		-- 3. Droppings, onto the garden's running dirt.
		for _, chicken in ipairs(chickens) do
			chicken.poopProgress = chicken.poopProgress + Tuning.POOP_RATE * dt
			while chicken.poopProgress >= chicken.poopThreshold do
				chicken.poopProgress = chicken.poopProgress - chicken.poopThreshold
				chicken.poopThreshold = Tuning.randomIn(Tuning.THRESHOLD_JITTER)
				chicken.droppings = chicken.droppings + 1
				dirt = dirt + Tuning.CLEAN_PENALTY_PER_DROPPING
			end
		end

		-- 4-5. Cleanliness, then laying at the step's values. An egg past
		-- the open bed slots lands on the floor and adds its dirt.
		local target = Gauges.cleanlinessTarget(dirt)
		for _, chicken in ipairs(chickens) do
			chicken.now = chicken.now + dt
			chicken.cleanliness = Gauges.easeCleanliness(chicken.cleanliness, target, dt)

			local bonus = Gauges.buffBonus(chicken.now - dt, chicken.happinessBuffExpiresAt, chicken.petBuffExpiresAt)
			local rate = Gauges.layRate(chicken.satiety, chicken.cleanliness, chicken.hydration, bonus)
			chicken.layProgress = chicken.layProgress + rate * stepHours
			if rate > 0 and chicken.layProgress >= chicken.layThreshold
				and chicken.now - chicken.lastLayAt >= Tuning.LAY_MIN_GAP then
				chicken.layProgress = chicken.layProgress - chicken.layThreshold
				chicken.layThreshold = Tuning.randomIn(Tuning.THRESHOLD_JITTER)
				chicken.lastLayAt = chicken.now
				chicken.eggs = chicken.eggs + 1
				if openSlots > 0 then
					openSlots = openSlots - 1
				else
					dirt = dirt + Tuning.CLEAN_PENALTY_PER_FLOOR_EGG
				end
			end
		end
	end

	return {
		hours = seconds / Tuning.HOUR,
		unitsConsumed = (input.units or 0) - units,
		waterConsumed = (input.water or 0) - water,
		chickens = chickens,
	}
end

return Offline
