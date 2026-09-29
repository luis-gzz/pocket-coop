local Tuning = require("src.systems.tuning")
local Gauges = require("src.objects.chicken.gauges")

-- Offline catch-up math (ADR-0016): given the state at close and how long
-- the app was away, computes where watching would have landed - in a few
-- closed-form phases, never by stepping through time. Pure data in, data
-- out; src/systems/garden.lua applies the result to the world. Every
-- constant comes from src/systems/tuning.lua, the same table the online
-- simulation reads.
local Offline = {}

-- Spends whole thresholds out of `progress`, resampling the threshold after
-- each - the same jittered accumulator the online gauges use. Returns the
-- count, leftover progress, and next threshold.
local function spendProgress(progress, threshold)
	local count = 0
	while progress >= threshold do
		progress = progress - threshold
		threshold = Tuning.randomIn(Tuning.THRESHOLD_JITTER)
		count = count + 1
	end
	return count, progress, threshold
end

-- input = {
--   units = total food units across every source,
--   dirtyItemCount = garden-wide dirty items at close,
--   chickens = { { satiety, poopProgress, poopThreshold, layProgress, layThreshold }, ... },
-- }
-- Returns { hours, fedHours, starvedHours, unitsConsumed, chickens = { {
-- satiety, droppings, poopProgress, poopThreshold, eggs, layProgress,
-- layThreshold }, ... } } in the same order as input.chickens.
function Offline.compute(input, elapsedSeconds)
	local seconds = math.max(0, math.min(elapsedSeconds, Tuning.OFFLINE_CAP))
	local hours = seconds / Tuning.HOUR
	local count = #input.chickens
	local perUnit = Tuning.SATIETY_PER_UNIT

	-- 1. Refill: the hungriest chickens eat first, each up to the fed
	-- plateau, out of the shared pool. Treated as happening at the start.
	local units = input.units
	local startSatiety = {}
	local order = {}
	for i, chicken in ipairs(input.chickens) do
		startSatiety[i] = chicken.satiety
		order[i] = i
	end
	table.sort(order, function(a, b)
		return startSatiety[a] < startSatiety[b]
	end)

	local ranDry = false
	for _, i in ipairs(order) do
		local needed = math.max(0, Tuning.FED_PLATEAU - startSatiety[i]) / perUnit
		if units >= needed then
			units = units - needed
			startSatiety[i] = math.max(startSatiety[i], Tuning.FED_PLATEAU)
		else
			startSatiety[i] = startSatiety[i] + units * perUnit
			units = 0
			ranDry = true
		end
	end

	-- 2. Fed: whatever's left keeps every chicken at the plateau.
	local fedHours = 0
	if not ranDry and count > 0 then
		fedHours = math.min(hours, units / (Tuning.FED_UNITS_PER_CHICKEN_HOUR * count))
	end
	local unitsConsumed = (input.units - units) + fedHours * Tuning.FED_UNITS_PER_CHICKEN_HOUR * count

	-- 3. Starved: decay from each chicken's phase-start value, stopping at
	-- the unfed floor (a chicken already below it forages back up to it).
	local starvedHours = hours - fedHours

	local targetAtClose = Gauges.cleanlinessTarget(input.dirtyItemCount)
	local results = {}
	local totalDroppings = 0
	for i, chicken in ipairs(input.chickens) do
		local satiety = startSatiety[i]
		if fedHours > 0 then
			-- A chicken above the plateau just decays down onto it.
			satiety = math.max(Tuning.FED_PLATEAU, satiety - Tuning.SATIETY_DECAY_PER_HOUR * fedHours)
		end
		local starvedStart = satiety
		local starvedMid = satiety
		if starvedHours > 0 then
			if starvedStart >= Tuning.UNFED_FLOOR then
				satiety = math.max(Tuning.UNFED_FLOOR, starvedStart - Tuning.SATIETY_DECAY_PER_HOUR * starvedHours)
			else
				satiety = Tuning.UNFED_FLOOR
			end
			starvedMid = (starvedHours > Tuning.UNFED_SETTLE_HOURS) and Tuning.UNFED_FLOOR
				or (starvedStart + satiety) / 2
		end

		-- 4. Droppings: the flat rate, on top of carried-over progress.
		local droppings, poopProgress, poopThreshold = spendProgress(
			chicken.poopProgress + hours * Tuning.POOP_PER_HOUR, chicken.poopThreshold
		)
		totalDroppings = totalDroppings + droppings

		results[i] = {
			satiety = satiety,
			starvedMid = starvedMid,
			droppings = droppings,
			poopProgress = poopProgress,
			poopThreshold = poopThreshold,
		}
	end

	-- 5. Eggs: two-phase happiness against the absence's average
	-- cleanliness. Floor eggs laid during the absence suppressing later
	-- laying is ignored - an accepted approximation.
	local targetAtReturn = Gauges.cleanlinessTarget(input.dirtyItemCount + totalDroppings)
	local cleanliness = (targetAtClose + targetAtReturn) / 2
	local fedRate = Gauges.layRatePerHour(Gauges.happinessFor(Tuning.FED_PLATEAU, cleanliness, false))
	local maxEggs = math.floor(hours * Tuning.HOUR / Tuning.LAY_MIN_GAP)

	for i, chicken in ipairs(input.chickens) do
		local result = results[i]
		local starvedRate = Gauges.layRatePerHour(Gauges.happinessFor(result.starvedMid, cleanliness, false))
		local progress = chicken.layProgress + fedHours * fedRate + starvedHours * starvedRate
		local eggs, layProgress, layThreshold = spendProgress(progress, chicken.layThreshold)
		if eggs > maxEggs then
			eggs = maxEggs
			-- Capped by the minimum gap - don't bank a burst for the return.
			layProgress = math.min(layProgress, layThreshold)
		end
		result.eggs = eggs
		result.layProgress = layProgress
		result.layThreshold = layThreshold
		result.starvedMid = nil
	end

	return {
		hours = hours,
		fedHours = fedHours,
		starvedHours = starvedHours,
		unitsConsumed = unitsConsumed,
		chickens = results,
	}
end

return Offline
