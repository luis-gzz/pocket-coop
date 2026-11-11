-- Plain-Lua checks for the pure sim modules (gauges, offline, tuning).
-- Run from the project root: lua tools/parity.lua
local Tuning = require("src.systems.tuning")
local Gauges = require("src.objects.chicken.gauges")
local Offline = require("src.systems.offline")

local failures = 0
local function check(name, ok, detail)
	print((ok and "PASS  " or "FAIL  ") .. name .. (detail and ("  [" .. detail .. "]") or ""))
	if not ok then
		failures = failures + 1
	end
end

local function hen(overrides)
	local chicken = {
		now = 0, satiety = 100, hydration = 100, cleanliness = 100,
		poopProgress = 0, poopThreshold = 1, layProgress = 0, layThreshold = 1,
	}
	for key, value in pairs(overrides or {}) do
		chicken[key] = value
	end
	return chicken
end

-- Averages `runs` offline passes (thresholds are jittered).
local function average(runs, makeInput, hours)
	local eggs, last
	eggs = 0
	for seed = 1, runs do
		math.randomseed(seed)
		last = Offline.compute(makeInput(), hours * Tuning.HOUR)
		eggs = eggs + last.chickens[1].eggs
	end
	return eggs / runs, last
end

local BOWL = Tuning.BOWL_WATER
local PATCH = 100

-- 1. Neglect: full hen, one seed patch, one full bowl, 24 h.
do
	local eggs, result = average(200, function()
		return { units = PATCH, water = BOWL, dirt = 0, openSlots = 3, chickens = { hen() } }
	end, 24)
	local chicken = result.chickens[1]
	check("neglect: about 1 egg", eggs >= 0.5 and eggs <= 2, string.format("%.2f eggs", eggs))
	check("neglect: satiety 0", chicken.satiety == 0)
	check("neglect: hydration 0", chicken.hydration == 0)
	check("neglect: pools drained", result.unitsConsumed == PATCH and result.waterConsumed == BOWL)
	check("neglect: laid in the first hours", chicken.eggs == 0 or chicken.lastLayAt < 9 * Tuning.HOUR,
		string.format("last lay at %.1f h", chicken.lastLayAt / Tuning.HOUR))
end

-- 2. Gate beats buff.
do
	local treat = Gauges.HAPPINESS_BUFF_AMOUNT
	check("gate: starving + treat reads 25", Gauges.happinessFor(0, 100, 100, treat) == 25)
	check("gate: starving lay rate 0", Gauges.layRate(0, 100, 100, treat) == 0)
	check("gate: starving face sad", Gauges.happinessFace(Gauges.happinessFor(0, 100, 100, treat)) == "sad")
	local at9 = Gauges.happinessFor(9, 100, 100, treat)
	check("gate: satiety 9 + treat is meh but not laying",
		Gauges.happinessFace(at9) == "meh" and Gauges.layRate(9, 100, 100, treat) == 0, string.format("%.1f", at9))
	-- Unscaled happiness for (5, 100, 5), to tell "worse one" from "both".
	local value = 5 * 100 / Tuning.HAPPINESS_SATIETY_KNEE
	local other = 5 * 100 / Tuning.HAPPINESS_HYDRATION_KNEE
	local weights = { 112 - value, 12, 112 - other }
	local base = (weights[1] * value + weights[2] * 100 + weights[3] * other) / (weights[1] + weights[2] + weights[3])
	check("multiplier: worse one only", math.abs(Gauges.happinessFor(5, 100, 5, 0) - base * 0.5) < 1e-9,
		string.format("%.2f, both would be %.2f", Gauges.happinessFor(5, 100, 5, 0), base * 0.25))
	check("buffs: larger of treat and pet", Gauges.buffBonus(10, 20, 20) == 25 and Gauges.buffBonus(10, 0, 20) == 10
		and Gauges.buffBonus(30, 20, 20) == 0)

	-- Banked progress can't fire while gated, and fires once fed.
	math.randomseed(1)
	local gauges = Gauges.new({ satiety = 0, layProgress = 5 })
	local _, laid = gauges:update(60, 0, 0, 0, false, false, true)
	check("gate: banked lay held while starving", not laid and gauges.layProgress == 5)
	gauges.satiety = 100
	_, laid = gauges:update(60, 0, 0, 0, false, false, true)
	check("gate: banked lay fires once fed", laid)

	gauges = Gauges.new({})
	gauges.now = 1000
	gauges:applyPetBuff()
	gauges.now = 1600
	gauges:applyPetBuff()
	check("pet buff: restarts, never adds time", gauges.petBuffExpiresAt == 1600 + 30 * 60 and gauges:getBuffBonus() == 10)
end

-- 3. Mess only: fed, watered, 9 droppings.
do
	local happiness = Gauges.happinessFor(100, 10, 100, 0)
	check("gate: dehydrated lay rate 0", Gauges.layRate(100, 100, 5, treat) == 0)
	check("mess: lay rate 0, sad face", Gauges.layRate(100, 10, 100, 0) == 0
		and Gauges.happinessFace(Gauges.happinessFor(100, 10, 100, 0)) == "sad")
	check("mess: under 33 with no gate", happiness < Tuning.LAY_HAPPINESS_GATE, string.format("%.1f", happiness))
end

-- 4 (offline half). Pools that outlast the absence leave the right amounts.
do
	math.randomseed(1)
	local result = Offline.compute(
		{ units = 5000, water = 5000, dirt = 0, openSlots = 3, chickens = { hen({ satiety = 90, hydration = 85 }) } },
		8 * Tuning.HOUR
	)
	check("fed: held at the plateaus",
		math.abs(result.chickens[1].satiety - 90) < 1e-6 and math.abs(result.chickens[1].hydration - 85) < 1e-6)
	check("fed: upkeep spent", math.abs(result.unitsConsumed - 800) < 1e-6 and math.abs(result.waterConsumed - 200) < 1e-6,
		string.format("%.1f units, %.1f water", result.unitsConsumed, result.waterConsumed))

	local nothing = Offline.compute({ units = 0, water = 0, dirt = 0, openSlots = 0, chickens = { hen() } }, 24 * Tuning.HOUR)
	check("nothing placed: both gauges 0", nothing.chickens[1].satiety == 0 and nothing.chickens[1].hydration == 0)

	-- Satisfied spell: 30 min at a quarter of the decay.
	local slow = Offline.compute(
		{ units = 0, water = 0, dirt = 0, chickens = { hen({ satisfiedUntil = 30 * 60 }) } }, 30 * 60
	)
	check("satisfied spell honoured", math.abs(slow.chickens[1].satiety - (100 - 12.5 * 0.5 * 0.25)) < 1e-6)

	-- Floor eggs: no open slots means every egg adds dirt.
	local full = Offline.compute(
		{ units = 1e6, water = 1e6, dirt = 0, openSlots = 0, chickens = { hen({ poopThreshold = 1e9 }) } }, 24 * Tuning.HOUR
	)
	local open = Offline.compute(
		{ units = 1e6, water = 1e6, dirt = 0, openSlots = 99, chickens = { hen({ poopThreshold = 1e9 }) } }, 24 * Tuning.HOUR
	)
	check("floor eggs dirty the garden", full.chickens[1].eggs > 0 and full.chickens[1].cleanliness < open.chickens[1].cleanliness,
		string.format("%d eggs, cleanliness %.1f vs %.1f", full.chickens[1].eggs, full.chickens[1].cleanliness, open.chickens[1].cleanliness))

	-- A treat buff counts for its remaining time only.
	local buffed = Offline.compute(
		{ units = 0, water = 1e6, dirt = 0, chickens = { hen({ satiety = 20, layProgress = 0, happinessBuffExpiresAt = 40 * 60 }) } },
		40 * 60
	)
	local plain = Offline.compute({ units = 0, water = 1e6, dirt = 0, chickens = { hen({ satiety = 20 }) } }, 40 * 60)
	check("treat buff counts while away", buffed.chickens[1].layProgress > plain.chickens[1].layProgress)
end

-- 5. Old save with hungerMode = "forage".
do
	local old = Gauges.new({ hungerMode = "forage", forageTrigger = 15, forageStop = 35, foodTrigger = 80, satiety = 30 })
	check("old save: forage loads as not hungry", old:isHungry() == false and old.foodTrigger == 80)
	check("old save: food mode loads as hungry", Gauges.new({ hungerMode = "food" }):isHungry() == true)
	old:update(1, 0, 0, 0, false, true, true)
	check("old save: hunger opens once food is out", old:isHungry())
	local data = old:getSaveData()
	check("save: no forage fields", data.hungerMode == nil and data.forageTrigger == nil and data.hungry == true)
end

-- 6. Step size: halving OFFLINE_STEP moves the egg count by at most one.
do
	local function scenario()
		return { units = 600, water = BOWL, dirt = 0, openSlots = 3, chickens = { hen() } }
	end
	local step = Tuning.OFFLINE_STEP
	local coarse = average(200, scenario, 24)
	Tuning.OFFLINE_STEP = step / 2
	local fine = average(200, scenario, 24)
	Tuning.OFFLINE_STEP = step
	check("step size: halving changes eggs by <= 1", math.abs(coarse - fine) <= 1, string.format("%.2f vs %.2f", coarse, fine))
end

print(failures == 0 and "\nAll checks passed." or ("\n" .. failures .. " check(s) failed."))
os.exit(failures == 0 and 0 or 1)
