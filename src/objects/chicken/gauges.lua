-- Per-chicken satiety/cleanliness/happiness model. Pure data + rates, no
-- display objects here (see src/objects/items/dropping.lua for the visual
-- side) - keeps this module the single place gauge math happens (ADR-0003).
--
-- Never requires Garden or Clock directly: dt is passed in already
-- time-scaled (from Clock, via Chicken), and dirtyItemCount (droppings +
-- floor eggs, now a garden-wide count) is passed in by Garden's own
-- per-frame loop. See garden.lua and chicken.lua.
local Gauges = {}
Gauges.__index = Gauges

-- Satiety: falls while idle/wander, rises while eating, capped at whichever
-- ceiling is in force (see rollWantsToEat/rollShouldStopEating).
local SATIETY_DECAY_RATE = 100 / 240 -- empty over 4 minutes of not eating
local SATIETY_EAT_RATE = 100 / 30 -- full over 30 seconds of active eating
local SATIETY_FORAGE_CEILING = 50 -- forage's satiety cap
local SATIETY_FOOD_CEILING = 100

-- Exposed so src/objects/chicken/chicken.lua can pick which ceiling to roll against.
Gauges.FORAGE_CEILING = SATIETY_FORAGE_CEILING
Gauges.FOOD_CEILING = SATIETY_FOOD_CEILING

-- Stop-eating chance is (satiety/ceiling)^exponent (see rollShouldStopEating).
-- Forage's exponent is higher than food's so satiety climbs closer to the
-- lower forage ceiling before the chance to quit gets meaningful.
local STOP_CHANCE_EXPONENT_FOOD = 3
local STOP_CHANCE_EXPONENT_FORAGE = 3

-- From a food source, satiety must close at least this fraction of the gap
-- to the ceiling that existed when eating started before rollShouldStopEating
-- will even consider ending it early (CONTEXT.md's Eat) - a hen that starts
-- out already mostly fed still eats a little instead of quitting almost
-- instantly. Forage gets no such floor; see Gauges:setEating.
local MIN_EAT_STOP_FRACTION = 0.5

-- Start-eating chance is ((ceiling-satiety)/ceiling)^exponent (see
-- rollWantsToEat). Forage's exponent is above 1 so the chance stays low
-- until satiety is genuinely low, rather than triggering readily at only
-- moderate hunger.
local START_CHANCE_EXPONENT_FOOD = 1
local START_CHANCE_EXPONENT_FORAGE = 1.6

-- Cleanliness: eases toward a target set by how many dirty items exist
-- garden-wide (ADR-0004), rather than draining directly.
local CLEAN_PENALTY_PER_DROPPING = 10
local CLEAN_EASE_RATE = 0.05 -- fraction of the remaining gap closed per second

-- Poop clock: a recurring, FSM-independent chance to spawn a dropping.
local POOP_CLOCK_INTERVAL = 60 -- seconds between rolls
local POOP_BASE_CHANCE = 0.15
local POOP_ATE_RECENTLY_BONUS = 0.25
local POOP_ATE_RECENTLY_WINDOW = 30 -- seconds; "recently" for the bonus above
local POOP_STALE_BONUS_PER_CYCLE = 0.1 -- ramps the longer it's been since the last spawn
local DROPPING_JITTER_RADIUS = 10 -- world points; scatters spawns near the chicken so stacked droppings stay visually distinct

-- Happiness buff: a flat, temporary bonus with an expiry, not stacked by a
-- repeat grant. Currently only a mealworm grants one.
local HAPPINESS_BUFF_AMOUNT = 25
local HAPPINESS_BUFF_DURATION = 5 * 60 -- seconds
local TREAT_SATIETY_BONUS = 25

-- Lay clock: a recurring, FSM-independent chance to lay an egg (CONTEXT.md),
-- shaped just like the poop clock above - an accumulator rolling a check
-- every LAY_CLOCK_INTERVAL. Gauges only gates WHEN a hen lays; src/systems/
-- garden.lua decides WHERE the egg goes, and the hen's own nest state
-- carries out the walk there (ADR-0007, ADR-0013).
local LAY_CLOCK_INTERVAL = 60 -- seconds between rolls
local LAY_HAPPINESS_GATE = 33 -- below this happiness, no laying at all
local LAY_REFRACTORY = 3 * 60 -- seconds since the last lay before laying is possible again
local LAY_HAPPINESS_MIN_FACTOR = 0.15 -- happiness_factor right at the happiness gate
local LAY_TIME_BASE = 0.3 -- time_factor right at the end of the refractory window
local LAY_TIME_STEP = 0.2 -- time_factor gained per minute past the refractory window

-- Happiness: weighted average of satiety/cleanliness where the worse of the
-- two pulls harder (lower K = harsher penalty for a lopsided pair).
local HAPPINESS_K = 12

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function clamp100(value)
	return clamp(value, 0, 100)
end

local function clamp01(value)
	return math.max(0, math.min(1, value))
end

-- saved: an optional table (from src/systems/save.lua) to resume from. All
-- fields live on the same internal `now` clock, which only advances while
-- the app is open - so resuming from a save is just picking that clock back
-- up, with no elapsed-time decay to compute (there deliberately isn't any
-- yet).
function Gauges.new(saved)
	saved = saved or {}
	local self = setmetatable({}, Gauges)

	self.satiety = saved.satiety or 100
	self.cleanliness = saved.cleanliness or 100
	self.happinessBuffExpiresAt = saved.happinessBuffExpiresAt or 0
	self.cyclesSincePoop = saved.cyclesSincePoop or 0
	self.poopClockAccumulator = saved.poopClockAccumulator or 0
	self.lastAteAt = saved.lastAteAt or -math.huge
	self.lastLayAt = saved.lastLayAt or -math.huge
	self.layClockAccumulator = saved.layClockAccumulator or 0
	self.now = saved.now or 0

	-- Set the moment a lay roll succeeds, cleared by markLaid() once the egg
	-- actually lands (ADR-0013) - not persisted, so an app quit mid-walk just
	-- loses that one lay attempt rather than needing its own save slot.
	self.pendingLay = false

	self.isEating = false
	self.eatCeiling = SATIETY_FOOD_CEILING
	self.eatStopExponent = STOP_CHANCE_EXPONENT_FOOD
	self.minSatietyBeforeStopRoll = self.satiety

	return self
end

-- ceiling: the satiety cap for this bout of eating (SATIETY_FOOD_CEILING or
-- SATIETY_FORAGE_CEILING). Ignored while isEating is false. Starting a food-
-- source bout (not forage) also fixes minSatietyBeforeStopRoll at the
-- current satiety plus MIN_EAT_STOP_FRACTION of the gap to the ceiling -
-- forage's is just its current satiety, i.e. no floor at all.
function Gauges:setEating(isEating, ceiling)
	self.isEating = isEating
	self.eatCeiling = ceiling or SATIETY_FOOD_CEILING
	local isForaging = self.eatCeiling == SATIETY_FORAGE_CEILING
	self.eatStopExponent = isForaging and STOP_CHANCE_EXPONENT_FORAGE or STOP_CHANCE_EXPONENT_FOOD

	if isEating then
		self.minSatietyBeforeStopRoll = isForaging and self.satiety
			or (self.satiety + (self.eatCeiling - self.satiety) * MIN_EAT_STOP_FRACTION)
	end
end

-- Chance to start eating, weighted by how far satiety sits below `ceiling` -
-- 100% at empty, 0% at or above it.
function Gauges:rollWantsToEat(ceiling)
	local exponent = (ceiling == SATIETY_FORAGE_CEILING) and START_CHANCE_EXPONENT_FORAGE or START_CHANCE_EXPONENT_FOOD
	local chance = clamp01((ceiling - self.satiety) / ceiling) ^ exponent
	return math.random() < chance
end

-- Chance to stop eating, rolled about once a second while eating. Below
-- minSatietyBeforeStopRoll (only ever above current satiety for a food
-- source, never for forage - see Gauges:setEating), always keeps eating; past
-- it, the chance rises the closer satiety already is to the ceiling.
function Gauges:rollShouldStopEating()
	if self.satiety >= self.eatCeiling then
		return true
	end
	if self.satiety < self.minSatietyBeforeStopRoll then
		return false
	end
	local chance = clamp01(self.satiety / self.eatCeiling) ^ self.eatStopExponent
	return math.random() < chance
end

local function rollPoopClock(self)
	local chance = POOP_BASE_CHANCE
	if self.now - self.lastAteAt <= POOP_ATE_RECENTLY_WINDOW then
		chance = chance + POOP_ATE_RECENTLY_BONUS
	end
	chance = chance + self.cyclesSincePoop * POOP_STALE_BONUS_PER_CYCLE

	if math.random() < chance then
		self.cyclesSincePoop = 0
		return true
	end

	self.cyclesSincePoop = self.cyclesSincePoop + 1
	return false
end

-- Gates on a lay already pending (a hen mid-walk-to-lay can't roll a second
-- one), happiness, and the refractory period, then rolls a chance that rises
-- with both happiness and time since the last lay. On success, sets
-- pendingLay (closing the gate above for any later roll until markLaid()
-- clears it) - lastLayAt itself only advances once the egg actually lands.
local function rollLayClock(self)
	if self.pendingLay then
		return false
	end

	local happiness = self:getHappiness()
	if happiness < LAY_HAPPINESS_GATE then
		return false
	end

	local secondsSinceLastLay = self.now - self.lastLayAt
	if secondsSinceLastLay < LAY_REFRACTORY then
		return false
	end

	local happinessNorm = (happiness - LAY_HAPPINESS_GATE) / (100 - LAY_HAPPINESS_GATE)
	local happinessFactor = LAY_HAPPINESS_MIN_FACTOR + (1 - LAY_HAPPINESS_MIN_FACTOR) * happinessNorm
	local minutesPastRefractory = (secondsSinceLastLay - LAY_REFRACTORY) / 60
	local timeFactor = clamp01(LAY_TIME_BASE + minutesPastRefractory * LAY_TIME_STEP)
	local layChance = clamp01(happinessFactor * timeFactor)

	if math.random() < layChance then
		self.pendingLay = true
		return true
	end
	return false
end

-- Offsets (x, y) by a random point inside DROPPING_JITTER_RADIUS, so
-- droppings spawned close together in time don't land on the exact same
-- pixel.
local function jitteredPosition(x, y)
	local angle = math.random() * math.pi * 2
	local radius = math.random() * DROPPING_JITTER_RADIUS
	return x + math.cos(angle) * radius, y + math.sin(angle) * radius
end

-- Advances the simulation by dt seconds (already clamped and time-scaled by
-- Clock). dirtyItemCount is the garden-wide dropping + floor egg count,
-- supplied by Garden's own frame loop. isHeld suppresses the lay clock
-- entirely (mirroring how a held hen also can't be claimed by a treat, see
-- chicken.lua), so a drag can never yank a hen out of a walk it hasn't even
-- started yet. Returns spawned droppings, whether a lay happened, and
-- satiety delivered this call.
function Gauges:update(dt, dirtyItemCount, chickenX, chickenY, isHeld)
	self.now = self.now + dt

	local satietyBefore = self.satiety
	if self.isEating then
		self.satiety = clamp(self.satiety + SATIETY_EAT_RATE * dt, 0, self.eatCeiling)
		self.lastAteAt = self.now
	else
		self.satiety = clamp100(self.satiety - SATIETY_DECAY_RATE * dt)
	end
	local delivered = math.max(0, self.satiety - satietyBefore)

	local target = clamp100(100 - dirtyItemCount * CLEAN_PENALTY_PER_DROPPING)
	self.cleanliness = self.cleanliness + (target - self.cleanliness) * CLEAN_EASE_RATE * dt

	local spawned = {}
	self.poopClockAccumulator = self.poopClockAccumulator + dt
	while self.poopClockAccumulator >= POOP_CLOCK_INTERVAL do
		self.poopClockAccumulator = self.poopClockAccumulator - POOP_CLOCK_INTERVAL
		if rollPoopClock(self) then
			local x, y = jitteredPosition(chickenX, chickenY)
			table.insert(spawned, { x = x, y = y, createdAt = self.now })
		end
	end

	local laid = false
	if not isHeld then
		self.layClockAccumulator = self.layClockAccumulator + dt
		while self.layClockAccumulator >= LAY_CLOCK_INTERVAL do
			self.layClockAccumulator = self.layClockAccumulator - LAY_CLOCK_INTERVAL
			if rollLayClock(self) then
				laid = true
			end
		end
	end

	return spawned, laid, delivered
end

-- Called once a pending lay actually lands (egg created), whether in a bed
-- or on the floor - advances the refractory window from here, not from when
-- the lay was decided, and reopens the gate for another roll (ADR-0013).
function Gauges:markLaid()
	self.lastLayAt = self.now
	self.pendingLay = false
end

-- Permanent satiety bump from a mealworm, uncapped by the forage ceiling.
function Gauges:applyTreatSatiety()
	self.satiety = clamp100(self.satiety + TREAT_SATIETY_BONUS)
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
	local satiety, cleanliness = self.satiety, self.cleanliness
	local weightSatiety = (100 - satiety) + HAPPINESS_K
	local weightCleanliness = (100 - cleanliness) + HAPPINESS_K
	local base = (weightSatiety * satiety + weightCleanliness * cleanliness) / (weightSatiety + weightCleanliness)

	local happinessBuff = self:isHappinessBuffActive() and HAPPINESS_BUFF_AMOUNT or 0
	return clamp100(base + happinessBuff)
end

function Gauges:getSaveData()
	return {
		satiety = self.satiety,
		cleanliness = self.cleanliness,
		happinessBuffExpiresAt = self.happinessBuffExpiresAt,
		cyclesSincePoop = self.cyclesSincePoop,
		poopClockAccumulator = self.poopClockAccumulator,
		lastAteAt = self.lastAteAt,
		lastLayAt = self.lastLayAt,
		layClockAccumulator = self.layClockAccumulator,
		now = self.now,
	}
end

return Gauges
