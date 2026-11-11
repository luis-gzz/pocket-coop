local Tuning = require("src.systems.tuning")

-- Per-chicken satiety/cleanliness/hydration/happiness math - pure data, no display
-- objects. Constants come from src/systems/tuning.lua (ADR-0016).
local Gauges = {}
Gauges.__index = Gauges

-- Scatters droppings spawned near the chicken so stacked ones stay visually
-- distinct.
local DROPPING_JITTER_RADIUS = 10 -- world points

-- Happiness buffs: flat, temporary bonuses; a repeat grant restarts the
-- duration, and only the larger active one applies. Treat, then pet.
Gauges.HAPPINESS_BUFF_AMOUNT = 25
local HAPPINESS_BUFF_DURATION = 60 * 60 -- seconds
Gauges.PET_BUFF_AMOUNT = 10
local PET_BUFF_DURATION = 30 * 60 -- seconds

-- Happiness: weighted average of the gauges where the worse ones pull
-- harder (lower K = harsher penalty for a lopsided set).
local HAPPINESS_K = 12

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function clamp100(value)
	return clamp(value, 0, 100)
end

-- The cleanliness a given garden-wide dirt (summed dirty-item penalties)
-- eases toward.
function Gauges.cleanlinessTarget(dirt)
	return clamp100(100 - dirt)
end

-- Eases cleanliness toward `target` over dt (ADR-0004). Closed form, so one
-- large dt lands exactly where many small frames would.
function Gauges.easeCleanliness(current, target, dt)
	return target + (current - target) * math.exp(-Tuning.CLEAN_EASE_RATE * dt)
end

-- Happiness as a pure function, shared with offline catch-up. Satiety and
-- hydration at or above their knees count as full.
function Gauges.happinessFor(satiety, cleanliness, hydration, bonus)
	local values = {
		clamp100(satiety * 100 / Tuning.HAPPINESS_SATIETY_KNEE),
		cleanliness,
		clamp100(hydration * 100 / Tuning.HAPPINESS_HYDRATION_KNEE),
	}
	local weighted, totalWeight = 0, 0
	for _, value in ipairs(values) do
		local weight = (100 - value) + HAPPINESS_K
		weighted = weighted + weight * value
		totalWeight = totalWeight + weight
	end
	local base = weighted / totalWeight
	-- Starving or dehydrated: scaled toward 0 by the worse of the two,
	-- before the buff, so a treat still shows (ADR-0019, ADR-0026).
	local scale = math.min(1, satiety / Tuning.LAY_SATIETY_GATE, hydration / Tuning.DEHYDRATED_BELOW)
	return clamp100(base * math.max(0, scale) + (bonus or 0))
end

-- The bonus from whichever happiness buffs are still running at `now`.
function Gauges.buffBonus(now, treatExpiresAt, petExpiresAt)
	if now < treatExpiresAt then
		return Gauges.HAPPINESS_BUFF_AMOUNT
	end
	return (now < petExpiresAt) and Gauges.PET_BUFF_AMOUNT or 0
end

-- Eggs per hour at happiness h: none below the gate, ramping from
-- LAY_MIN_RATE_FACTOR to the full base rate at LAY_FULL_RATE_HAPPINESS.
function Gauges.layRatePerHour(happiness)
	if happiness < Tuning.LAY_HAPPINESS_GATE then
		return 0
	end
	if happiness >= Tuning.LAY_FULL_RATE_HAPPINESS then
		return Tuning.LAY_BASE_PER_HOUR
	end
	local t = (happiness - Tuning.LAY_HAPPINESS_GATE) / (Tuning.LAY_FULL_RATE_HAPPINESS - Tuning.LAY_HAPPINESS_GATE)
	return Tuning.LAY_BASE_PER_HOUR * (Tuning.LAY_MIN_RATE_FACTOR + (1 - Tuning.LAY_MIN_RATE_FACTOR) * t)
end

-- Eggs per hour, shared with offline catch-up: none while a lay gate fails
-- (ADR-0026), else what happiness allows.
function Gauges.layRate(satiety, cleanliness, hydration, bonus)
	if satiety < Tuning.LAY_SATIETY_GATE or hydration < Tuning.DEHYDRATED_BELOW then
		return 0
	end
	return Gauges.layRatePerHour(Gauges.happinessFor(satiety, cleanliness, hydration, bonus))
end

-- "sad" while she can't lay, "meh" at a reduced lay rate, "happy" at the full rate.
function Gauges.happinessFace(happiness)
	if happiness < Tuning.LAY_HAPPINESS_GATE then
		return "sad"
	end
	return happiness >= Tuning.LAY_FULL_RATE_HAPPINESS and "happy" or "meh"
end

-- saved: an optional table to resume from. Timestamps use the internal
-- `now`, which offline catch-up advances by the time away (ADR-0016).
function Gauges.new(saved)
	saved = saved or {}
	local self = setmetatable({}, Gauges)

	self.now = saved.now or 0
	self.satiety = saved.satiety or 100
	self.cleanliness = saved.cleanliness or 100
	self.hydration = saved.hydration or 100
	self.happinessBuffExpiresAt = saved.happinessBuffExpiresAt or 0
	self.petBuffExpiresAt = saved.petBuffExpiresAt or 0
	self.satisfiedUntil = saved.satisfiedUntil or 0

	-- Hunger (ADR-0015): open from crossing foodTrigger (with food around)
	-- until 100. hungerMode is the pre-ADR-0026 save field.
	self.hungry = saved.hungry or saved.hungerMode == "food"
	self.foodTrigger = saved.foodTrigger or Tuning.randomIn(Tuning.FOOD_TRIGGER)

	-- Thirst: open from crossing thirstTrigger (with water around) until 100.
	self.thirsty = saved.thirsty or false
	self.thirstTrigger = saved.thirstTrigger or Tuning.randomIn(Tuning.THIRST_TRIGGER)

	self.poopProgress = saved.poopProgress or 0
	self.poopThreshold = saved.poopThreshold or Tuning.randomIn(Tuning.THRESHOLD_JITTER)
	self.layProgress = saved.layProgress or 0
	self.layThreshold = saved.layThreshold or Tuning.randomIn(Tuning.THRESHOLD_JITTER)
	self.lastLayAt = saved.lastLayAt or -math.huge

	-- Set when lay progress fires, cleared by markLaid() once the egg lands
	-- (ADR-0013). Not persisted - a quit mid-walk just re-fires next launch.
	self.pendingLay = false

	self.isEating = false
	self.eatingPaused = false
	self.boutTarget = nil
	self.isDrinking = false

	return self
end

local function endHungerCycle(self)
	self.hungry = false
	self.foodTrigger = Tuning.randomIn(Tuning.FOOD_TRIGGER)
end

-- Clears any in-progress hunger cycle and bout, e.g. after offline catch-up
-- replaces satiety wholesale.
function Gauges:resetHunger()
	self.isEating = false
	self.eatingPaused = false
	self.boutTarget = nil
	endHungerCycle(self)
end

local function endThirst(self)
	self.thirsty = false
	self.thirstTrigger = Tuning.randomIn(Tuning.THIRST_TRIGGER)
end

-- Clears any in-progress thirst, e.g. after offline catch-up.
function Gauges:resetThirst()
	self.isDrinking = false
	endThirst(self)
end

function Gauges:isThirsty()
	return self.thirsty
end

function Gauges:startDrinking()
	self.isDrinking = true
end

function Gauges:stopDrinking()
	self.isDrinking = false
end

function Gauges:isHungry()
	return self.hungry
end

-- Starts one bout: half the gap to 100 (all of it once small).
function Gauges:startBout()
	self.isEating = true
	self.eatingPaused = false
	local gap = Tuning.FOOD_CEILING - self.satiety
	self.boutTarget = (gap <= Tuning.BOUT_FINISH_GAP) and Tuning.FOOD_CEILING or (self.satiety + gap / 2)
end

function Gauges:stopEating()
	self.isEating = false
	self.eatingPaused = false
	self.boutTarget = nil
end

-- Holds a bout mid-way (hopping between seeds): satiety neither rises nor falls.
function Gauges:setEatingPaused(value)
	self.eatingPaused = value
end

local function randomPointNear(x, y, radius)
	local angle = math.random() * math.pi * 2
	local distance = math.random() * radius
	return x + math.cos(angle) * distance, y + math.sin(angle) * distance
end

function Gauges:isSatisfied()
	return self.now < self.satisfiedUntil
end

-- Advances by dt (time-scaled). Returns spawned droppings, whether a lay
-- fired (never while held), satiety delivered, whether the bout finished,
-- and hydration drunk.
function Gauges:update(dt, dirt, chickenX, chickenY, isHeld, hasSource, hasWater)
	self.now = self.now + dt

	local satietyBefore = self.satiety
	local boutDone = false
	if self.isEating and self.boutTarget then
		if not self.eatingPaused then
			self.satiety = math.min(self.boutTarget, self.satiety + Tuning.SATIETY_EAT_RATE * dt)
			boutDone = self.satiety >= self.boutTarget
		end
	elseif not self.isEating then
		local rate = Tuning.SATIETY_DECAY_RATE
		if self:isSatisfied() then
			rate = rate * Tuning.SATISFIED_DECAY_FACTOR
		end
		self.satiety = clamp100(self.satiety - rate * dt)
	end
	local delivered = math.max(0, self.satiety - satietyBefore)

	if satietyBefore < Tuning.FOOD_CEILING and self.satiety >= Tuning.FOOD_CEILING then
		self.satisfiedUntil = self.now + Tuning.SATISFIED_DURATION
	end

	-- Like thirst, hunger follows whether food exists right now.
	if not hasSource then
		self.hungry = false
	elseif self.satiety < self.foodTrigger then
		self.hungry = true
	end
	if self.hungry and self.satiety >= Tuning.FOOD_CEILING then
		endHungerCycle(self)
	end

	local hydrationBefore = self.hydration
	if self.isDrinking then
		self.hydration = math.min(100, self.hydration + Tuning.HYDRATION_DRINK_RATE * dt)
	else
		self.hydration = clamp100(self.hydration - Tuning.HYDRATION_DECAY_RATE * dt)
	end
	local drank = math.max(0, self.hydration - hydrationBefore)

	-- Thirst follows whether water exists right now.
	if not hasWater then
		self.thirsty = false
	elseif self.hydration < self.thirstTrigger then
		self.thirsty = true
	end
	if self.thirsty and self.hydration >= 100 then
		endThirst(self)
	end

	self.cleanliness = Gauges.easeCleanliness(self.cleanliness, Gauges.cleanlinessTarget(dirt), dt)

	local spawned = {}
	self.poopProgress = self.poopProgress + Tuning.POOP_RATE * dt
	while self.poopProgress >= self.poopThreshold do
		self.poopProgress = self.poopProgress - self.poopThreshold
		self.poopThreshold = Tuning.randomIn(Tuning.THRESHOLD_JITTER)
		local x, y = randomPointNear(chickenX, chickenY, DROPPING_JITTER_RADIUS)
		table.insert(spawned, { x = x, y = y, createdAt = self.now })
	end

	-- A gated hen's progress holds, and banked progress can't fire (ADR-0026).
	local layRate = self:getLayRate()
	self.layProgress = self.layProgress + layRate / Tuning.HOUR * dt
	local laid = false
	if not self.pendingLay and not isHeld and layRate > 0
		and self.layProgress >= self.layThreshold
		and self.now - self.lastLayAt >= Tuning.LAY_MIN_GAP then
		self.pendingLay = true
		laid = true
	end

	return spawned, laid, delivered, boutDone, drank
end

-- Called once a pending egg lands: spends the progress and starts the
-- minimum gap from here (ADR-0013).
function Gauges:markLaid()
	self.layProgress = math.max(0, self.layProgress - self.layThreshold)
	self.layThreshold = Tuning.randomIn(Tuning.THRESHOLD_JITTER)
	self.lastLayAt = self.now
	self.pendingLay = false
end

-- Instant satiety from a mealworm. Reaching 100 grants the satisfied buff
-- like any meal.
function Gauges:applySatiety(amount)
	local before = self.satiety
	self.satiety = clamp100(self.satiety + amount)
	if before < Tuning.FOOD_CEILING and self.satiety >= Tuning.FOOD_CEILING then
		self.satisfiedUntil = self.now + Tuning.SATISFIED_DURATION
	end
end

-- Instant cleanliness from ash; it then eases back toward the dirt
-- target like any other value (ADR-0004).
function Gauges:applyCleanliness(amount)
	self.cleanliness = clamp100(self.cleanliness + amount)
end

-- Instant hydration from a watermelon slice; topping off ends any thirst.
function Gauges:applyHydration(amount)
	self.hydration = clamp100(self.hydration + amount)
	if self.hydration >= 100 then
		endThirst(self)
	end
end

-- Grants (or restarts) the happiness buff - called when a chicken finishes
-- any treat.
function Gauges:applyHappinessBuff()
	self.happinessBuffExpiresAt = self.now + HAPPINESS_BUFF_DURATION
end

-- Grants the pet buff: 30 minutes from now, never added to what's left.
function Gauges:applyPetBuff()
	self.petBuffExpiresAt = self.now + PET_BUFF_DURATION
end

function Gauges:getBuffBonus()
	return Gauges.buffBonus(self.now, self.happinessBuffExpiresAt, self.petBuffExpiresAt)
end

function Gauges:getHappiness()
	return Gauges.happinessFor(self.satiety, self.cleanliness, self.hydration, self:getBuffBonus())
end

function Gauges:getLayRate()
	return Gauges.layRate(self.satiety, self.cleanliness, self.hydration, self:getBuffBonus())
end

function Gauges:getSaveData()
	return {
		now = self.now,
		satiety = self.satiety,
		cleanliness = self.cleanliness,
		hydration = self.hydration,
		thirsty = self.thirsty,
		thirstTrigger = self.thirstTrigger,
		happinessBuffExpiresAt = self.happinessBuffExpiresAt,
		petBuffExpiresAt = self.petBuffExpiresAt,
		satisfiedUntil = self.satisfiedUntil,
		hungry = self.hungry,
		foodTrigger = self.foodTrigger,
		poopProgress = self.poopProgress,
		poopThreshold = self.poopThreshold,
		layProgress = self.layProgress,
		layThreshold = self.layThreshold,
		-- -math.huge ("never laid") doesn't survive JSON; nil reloads as it.
		lastLayAt = (self.lastLayAt > -math.huge) and self.lastLayAt or nil,
	}
end

return Gauges
