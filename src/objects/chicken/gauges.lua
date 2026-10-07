local Tuning = require("src.systems.tuning")

-- Per-chicken satiety/cleanliness/happiness math - pure data, no display
-- objects. Constants come from src/systems/tuning.lua (ADR-0016).
local Gauges = {}
Gauges.__index = Gauges

-- Scatters droppings spawned near the chicken so stacked ones stay visually
-- distinct.
local DROPPING_JITTER_RADIUS = 10 -- world points

-- Happiness buff: a flat, temporary bonus with an expiry, not stacked by a
-- repeat grant. Currently only a mealworm grants one.
local HAPPINESS_BUFF_AMOUNT = 25
local HAPPINESS_BUFF_DURATION = 5 * 60 -- seconds

-- Happiness: weighted average of satiety/cleanliness where the worse of the
-- two pulls harder (lower K = harsher penalty for a lopsided pair).
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

-- Happiness as a pure function, shared with offline catch-up. Satiety at or
-- above HAPPINESS_SATIETY_KNEE counts as fully fed.
function Gauges.happinessFor(satiety, cleanliness, buffActive)
	satiety = clamp100(satiety * 100 / Tuning.HAPPINESS_SATIETY_KNEE)
	local weightSatiety = (100 - satiety) + HAPPINESS_K
	local weightCleanliness = (100 - cleanliness) + HAPPINESS_K
	local base = (weightSatiety * satiety + weightCleanliness * cleanliness) / (weightSatiety + weightCleanliness)
	return clamp100(base + (buffActive and HAPPINESS_BUFF_AMOUNT or 0))
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

-- saved: an optional table to resume from. Timestamps use the internal
-- `now`, which offline catch-up advances by the time away (ADR-0016).
function Gauges.new(saved)
	saved = saved or {}
	local self = setmetatable({}, Gauges)

	self.now = saved.now or 0
	self.satiety = saved.satiety or 100
	self.cleanliness = saved.cleanliness or 100
	-- Pinned full until water exists; not saved and not part of happiness yet.
	self.hydration = 100
	self.happinessBuffExpiresAt = saved.happinessBuffExpiresAt or 0
	self.satisfiedUntil = saved.satisfiedUntil or 0

	-- Hunger cycle (ADR-0015): nil while not hungry, else "food" (eating in
	-- bouts until 100) or "forage" (eating until forageStop).
	self.hungerMode = saved.hungerMode
	self.foodTrigger = saved.foodTrigger
	self.forageTrigger = saved.forageTrigger
	self.forageStop = saved.forageStop
	if not (self.foodTrigger and self.forageTrigger and self.forageStop) then
		self:resampleTriggers()
	end

	self.poopProgress = saved.poopProgress or 0
	self.poopThreshold = saved.poopThreshold or Tuning.randomIn(Tuning.THRESHOLD_JITTER)
	self.layProgress = saved.layProgress or 0
	self.layThreshold = saved.layThreshold or Tuning.randomIn(Tuning.THRESHOLD_JITTER)
	self.lastLayAt = saved.lastLayAt or -math.huge

	-- Set when lay progress fires, cleared by markLaid() once the egg lands
	-- (ADR-0013). Not persisted - a quit mid-walk just re-fires next launch.
	self.pendingLay = false

	self.isEating = false
	self.boutTarget = nil

	return self
end

-- Samples the satiety levels at which the next hunger cycle begins (one per
-- mode) and where a forage cycle ends.
function Gauges:resampleTriggers()
	self.foodTrigger = Tuning.randomIn(Tuning.FOOD_TRIGGER)
	self.forageTrigger = Tuning.randomIn(Tuning.FORAGE_TRIGGER)
	self.forageStop = Tuning.randomIn(Tuning.FORAGE_STOP)
end

local function endHungerCycle(self)
	self.hungerMode = nil
	self:resampleTriggers()
end

-- Clears any in-progress hunger cycle and bout, e.g. after offline catch-up
-- replaces satiety wholesale.
function Gauges:resetHunger()
	self.isEating = false
	self.boutTarget = nil
	endHungerCycle(self)
end

function Gauges:isHungry()
	return self.hungerMode ~= nil
end

function Gauges:getHungerMode()
	return self.hungerMode
end

-- Starts one bout: half the gap to 100 from a source (all of it once small),
-- or up to forageStop when foraging.
function Gauges:startBout(fromSource)
	self.isEating = true
	if fromSource then
		local gap = Tuning.FOOD_CEILING - self.satiety
		self.boutTarget = (gap <= Tuning.BOUT_FINISH_GAP) and Tuning.FOOD_CEILING or (self.satiety + gap / 2)
	else
		self.boutTarget = math.min(self.forageStop, Tuning.FORAGE_CEILING)
	end
end

function Gauges:stopEating()
	self.isEating = false
	self.boutTarget = nil
end

-- Mode follows whether food exists right now; placing or running out of food
-- switches it mid-cycle.
local function updateHungerMode(self, hasSource)
	local mode = hasSource and "food" or "forage"
	if self.hungerMode == mode then
		return
	end
	if mode == "food" then
		if self.hungerMode or self.satiety < self.foodTrigger then
			self.hungerMode = "food"
		end
	else
		self.hungerMode = (self.satiety < self.forageTrigger) and "forage" or nil
	end
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
-- fired (never while held), satiety delivered, and whether the bout finished.
function Gauges:update(dt, dirt, chickenX, chickenY, isHeld, hasSource)
	self.now = self.now + dt

	local satietyBefore = self.satiety
	local boutDone = false
	if self.isEating and self.boutTarget then
		self.satiety = math.min(self.boutTarget, self.satiety + Tuning.SATIETY_EAT_RATE * dt)
		boutDone = self.satiety >= self.boutTarget
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

	updateHungerMode(self, hasSource)
	if self.hungerMode == "food" and self.satiety >= Tuning.FOOD_CEILING then
		endHungerCycle(self)
	elseif self.hungerMode == "forage" and self.satiety >= self.forageStop then
		endHungerCycle(self)
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

	self.layProgress = self.layProgress + Gauges.layRatePerHour(self:getHappiness()) / Tuning.HOUR * dt
	local laid = false
	if not self.pendingLay and not isHeld
		and self.layProgress >= self.layThreshold
		and self.now - self.lastLayAt >= Tuning.LAY_MIN_GAP then
		self.pendingLay = true
		laid = true
	end

	return spawned, laid, delivered, boutDone
end

-- Called once a pending egg lands: spends the progress and starts the
-- minimum gap from here (ADR-0013).
function Gauges:markLaid()
	self.layProgress = math.max(0, self.layProgress - self.layThreshold)
	self.layThreshold = Tuning.randomIn(Tuning.THRESHOLD_JITTER)
	self.lastLayAt = self.now
	self.pendingLay = false
end

-- Instant satiety from a treat (amount per treat type). Reaching 100 grants
-- the satisfied buff like any meal.
function Gauges:applyTreat(amount)
	local before = self.satiety
	self.satiety = clamp100(self.satiety + amount)
	if before < Tuning.FOOD_CEILING and self.satiety >= Tuning.FOOD_CEILING then
		self.satisfiedUntil = self.now + Tuning.SATISFIED_DURATION
	end
end

-- Grants the happiness buff (see isHappinessBuffActive) - currently only
-- called when a chicken finishes eating a mealworm.
function Gauges:applyHappinessBuff()
	self.happinessBuffExpiresAt = self.now + HAPPINESS_BUFF_DURATION
end

function Gauges:isHappinessBuffActive()
	return self.now < self.happinessBuffExpiresAt
end

function Gauges:getHappiness()
	return Gauges.happinessFor(self.satiety, self.cleanliness, self:isHappinessBuffActive())
end

function Gauges:getSaveData()
	return {
		now = self.now,
		satiety = self.satiety,
		cleanliness = self.cleanliness,
		happinessBuffExpiresAt = self.happinessBuffExpiresAt,
		satisfiedUntil = self.satisfiedUntil,
		hungerMode = self.hungerMode,
		foodTrigger = self.foodTrigger,
		forageTrigger = self.forageTrigger,
		forageStop = self.forageStop,
		poopProgress = self.poopProgress,
		poopThreshold = self.poopThreshold,
		layProgress = self.layProgress,
		layThreshold = self.layThreshold,
		-- -math.huge ("never laid") doesn't survive JSON; nil reloads as it.
		lastLayAt = (self.lastLayAt > -math.huge) and self.lastLayAt or nil,
	}
end

return Gauges
