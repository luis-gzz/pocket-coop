local Tuning = require("src.systems.tuning")
local Gauges = require("src.objects.chicken.gauges")

-- Offline catch-up math (ADR-0016): closed-form phases, never stepping time.
-- Pure data in and out; garden.lua applies the result.
local Offline = {}

-- Spends whole jittered thresholds out of `progress`, like the online gauges.
-- Returns the count, leftover progress, and next threshold.
local function spendProgress(progress, threshold)
	local count = 0
	while progress >= threshold do
		progress = progress - threshold
		threshold = Tuning.randomIn(Tuning.THRESHOLD_JITTER)
		count = count + 1
	end
	return count, progress, threshold
end

-- Shares `pool` out thirstiest/hungriest first, raising each value up to
-- `plateau` at `perPoint` pool per gauge point. Returns the new values,
-- what's left, and whether it ran dry.
local function refill(values, pool, plateau, perPoint)
	local result, order = {}, {}
	for i, value in ipairs(values) do
		result[i] = value
		order[i] = i
	end
	table.sort(order, function(a, b)
		return result[a] < result[b]
	end)
	local ranDry = false
	for _, i in ipairs(order) do
		local needed = math.max(0, plateau - result[i]) * perPoint
		if pool >= needed then
			pool = pool - needed
			result[i] = math.max(result[i], plateau)
		else
			result[i] = result[i] + pool / perPoint
			pool = 0
			ranDry = true
		end
	end
	return result, pool, ranDry
end

-- Simpson's-rule average of f over [a, b] - happiness bends (knees, the
-- dehydration multiplier), so a straight midpoint undercounts.
local function averageOver(f, a, b)
	return (f(a) + 4 * f((a + b) / 2) + f(b)) / 6
end

-- input: { units, water, dirt, chickens = { {satiety, hydration, poop/lay
-- progress + thresholds} } }. Returns phase hours, unitsConsumed,
-- waterConsumed, per-chicken results.
function Offline.compute(input, elapsedSeconds)
	local seconds = math.max(0, math.min(elapsedSeconds, Tuning.OFFLINE_CAP))
	local hours = seconds / Tuning.HOUR
	local count = #input.chickens
	local perUnit = Tuning.SATIETY_PER_UNIT

	-- 1. Refill: the hungriest chickens eat first, each up to the fed
	-- plateau, out of the shared pool. Treated as happening at the start.
	local satieties, hydrations = {}, {}
	for i, chicken in ipairs(input.chickens) do
		satieties[i] = chicken.satiety
		hydrations[i] = chicken.hydration
	end
	local startSatiety, units, ranDry = refill(satieties, input.units, Tuning.FED_PLATEAU, 1 / perUnit)

	-- 2. Fed: whatever's left keeps every chicken at the plateau.
	local fedHours = 0
	if not ranDry and count > 0 then
		fedHours = math.min(hours, units / (Tuning.FED_UNITS_PER_CHICKEN_HOUR * count))
	end
	local unitsConsumed = (input.units - units) + fedHours * Tuning.FED_UNITS_PER_CHICKEN_HOUR * count
	if ranDry or fedHours < hours then
		unitsConsumed = input.units -- ran out: exact, so rounding can't leave a crumb
	end

	-- Water mirrors food: refill to the watered plateau, hold there while
	-- bowls last, then drain toward 0 (water is measured in hydration).
	local water = input.water or 0
	local startHydration, waterLeft, waterRanDry = refill(hydrations, water, Tuning.WATERED_PLATEAU, 1)
	local wateredHours = 0
	if not waterRanDry and count > 0 then
		wateredHours = math.min(hours, waterLeft / (Tuning.HYDRATION_DECAY_PER_HOUR * count))
	end
	local waterConsumed = (water - waterLeft) + wateredHours * Tuning.HYDRATION_DECAY_PER_HOUR * count
	if waterRanDry or wateredHours < hours then
		waterConsumed = water
	end

	-- 3. Starved: decay from each chicken's phase-start value, stopping at
	-- the unfed floor (a chicken already below it forages back up to it).
	local starvedHours = hours - fedHours

	local targetAtClose = Gauges.cleanlinessTarget(input.dirt)
	local results = {}
	local totalDroppings = 0
	for i, chicken in ipairs(input.chickens) do
		local satiety = startSatiety[i]
		if fedHours > 0 then
			-- A chicken above the plateau just decays down onto it.
			satiety = math.max(Tuning.FED_PLATEAU, satiety - Tuning.SATIETY_DECAY_PER_HOUR * fedHours)
		end
		local starvedStart = satiety
		local function satietyAt(t)
			if t <= fedHours then
				return Tuning.FED_PLATEAU
			end
			if starvedStart < Tuning.UNFED_FLOOR then
				return Tuning.UNFED_FLOOR
			end
			return math.max(Tuning.UNFED_FLOOR, starvedStart - Tuning.SATIETY_DECAY_PER_HOUR * (t - fedHours))
		end
		satiety = (starvedHours > 0) and satietyAt(hours) or satiety

		local hydration = startHydration[i]
		if wateredHours > 0 then
			hydration = math.max(Tuning.WATERED_PLATEAU, hydration - Tuning.HYDRATION_DECAY_PER_HOUR * wateredHours)
		end
		local dryStart = hydration
		local function hydrationAt(t)
			if t <= wateredHours then
				return Tuning.WATERED_PLATEAU
			end
			return math.max(0, dryStart - Tuning.HYDRATION_DECAY_PER_HOUR * (t - wateredHours))
		end
		hydration = (hours > wateredHours) and hydrationAt(hours) or hydration

		-- 4. Droppings: the flat rate, on top of carried-over progress.
		local droppings, poopProgress, poopThreshold = spendProgress(
			chicken.poopProgress + hours * Tuning.POOP_PER_HOUR, chicken.poopThreshold
		)
		totalDroppings = totalDroppings + droppings

		results[i] = {
			satiety = satiety,
			hydration = hydration,
			satietyAt = satietyAt,
			hydrationAt = hydrationAt,
			dryStart = dryStart,
			starvedStart = starvedStart,
			droppings = droppings,
			poopProgress = poopProgress,
			poopThreshold = poopThreshold,
		}
	end

	-- 5. Eggs: lay rate averaged over segments split wherever food or water
	-- runs out or hydration bends, against the absence's average cleanliness
	-- (floor eggs suppressing later laying is ignored).
	local targetAtReturn = Gauges.cleanlinessTarget(input.dirt + totalDroppings * Tuning.CLEAN_PENALTY_PER_DROPPING)
	local cleanliness = (targetAtClose + targetAtReturn) / 2
	local maxEggs = math.floor(hours * Tuning.HOUR / Tuning.LAY_MIN_GAP)

	for i, chicken in ipairs(input.chickens) do
		local result = results[i]
		local function rateAt(t)
			local happiness = Gauges.happinessFor(result.satietyAt(t), cleanliness, result.hydrationAt(t), false)
			return Gauges.layRatePerHour(happiness)
		end
		local decay = Tuning.HYDRATION_DECAY_PER_HOUR
		local breaks = {
			0, fedHours, wateredHours,
			fedHours + (result.starvedStart - Tuning.UNFED_FLOOR) / Tuning.SATIETY_DECAY_PER_HOUR,
			wateredHours + (result.dryStart - Tuning.DEHYDRATED_BELOW) / decay,
			wateredHours + result.dryStart / decay,
			hours,
		}
		table.sort(breaks)
		local progress = chicken.layProgress
		local previous = 0
		for _, t in ipairs(breaks) do
			t = math.max(0, math.min(hours, t))
			if t > previous then
				progress = progress + (t - previous) * averageOver(rateAt, previous, t)
				previous = t
			end
		end
		local eggs, layProgress, layThreshold = spendProgress(progress, chicken.layThreshold)
		if eggs > maxEggs then
			eggs = maxEggs
			-- Capped by the minimum gap - don't bank a burst for the return.
			layProgress = math.min(layProgress, layThreshold)
		end
		result.eggs = eggs
		result.layProgress = layProgress
		result.layThreshold = layThreshold
		result.satietyAt, result.hydrationAt, result.dryStart, result.starvedStart = nil, nil, nil, nil
	end

	return {
		hours = hours,
		fedHours = fedHours,
		starvedHours = starvedHours,
		wateredHours = wateredHours,
		unitsConsumed = unitsConsumed,
		waterConsumed = waterConsumed,
		chickens = results,
	}
end

return Offline
