local Coop = require("src.coop")

-- Per-chicken satiety/cleanliness/happiness model. Pure data + rates, no
-- display objects here (see src/dropping.lua for the visual side) - keeps
-- this module the single place gauge math happens (ADR-0003).
local Gauges = {}
Gauges.__index = Gauges

-- Satiety: falls while idle/wander, rises while eating.
local SATIETY_DECAY_RATE = 100 / 240 -- empty over 4 minutes of not eating
local SATIETY_EAT_RATE = 100 / 30 -- full over 30 seconds of active eating
local EAT_ENTER_THRESHOLD = 50 -- enter Eat once satiety drops below this
local EAT_EXIT_THRESHOLD = 80 -- stay in Eat until satiety climbs above this

-- Cleanliness: eases toward a target set by how many droppings exist
-- (ADR-0004), rather than draining directly.
local CLEAN_PENALTY_PER_DROPPING = 10
local CLEAN_EASE_RATE = 0.05 -- fraction of the remaining gap closed per second

-- Poop clock: a recurring, FSM-independent chance to spawn a dropping.
local POOP_CLOCK_INTERVAL = 60 -- seconds between rolls
local POOP_BASE_CHANCE = 0.15
local POOP_ATE_RECENTLY_BONUS = 0.25
local POOP_ATE_RECENTLY_WINDOW = 30 -- seconds; "recently" for the bonus above
local POOP_STALE_BONUS_PER_CYCLE = 0.1 -- ramps the longer it's been since the last spawn
local DROPPING_JITTER_RADIUS = 10 -- world points; scatters spawns near the chicken so stacked droppings stay visually distinct

-- Caps how much simulated time a single update() call can cover, regardless
-- of the debug time-scale multiplier. Without this, a frame hitch (or the
-- app losing/regaining focus) can produce one huge raw dt, which at a high
-- time-scale would blow through many poop-clock intervals in a single call -
-- several of which can succeed, all spawned at the same spot since the
-- chicken hasn't moved. Clamping the raw dt keeps the time-scale dial's
-- intended fast-forwarding (raw dt x up to 300) working at normal frame
-- rates while bounding worst-case bursts.
local MAX_RAW_DT = 0.25 -- seconds

-- Pet buff: flat happiness bonus with an expiry, refreshed (not stacked) by
-- re-petting.
local PET_BUFF_AMOUNT = 20
local PET_BUFF_DURATION = 5 * 60 -- seconds

-- Lay clock: a recurring, FSM-independent chance to lay an egg (CONTEXT.md),
-- shaped just like the poop clock above - an accumulator rolling a check
-- every LAY_CLOCK_INTERVAL. Gauges only gates WHEN a hen lays; src/coop.lua
-- decides WHERE the egg goes (ADR-0007).
local LAY_CLOCK_INTERVAL = 60 -- seconds between rolls
local LAY_HAPPINESS_GATE = 33 -- below this happiness, no laying at all
local LAY_REFRACTORY = 3 * 60 -- seconds since the last lay before laying is possible again
local LAY_HAPPINESS_MIN_FACTOR = 0.15 -- happiness_factor right at the happiness gate
local LAY_TIME_BASE = 0.3 -- time_factor right at the end of the refractory window
local LAY_TIME_STEP = 0.2 -- time_factor gained per minute past the refractory window

-- Happiness: weighted average of satiety/cleanliness where the worse of the
-- two pulls harder (lower K = harsher penalty for a lopsided pair).
local HAPPINESS_K = 12

local function clamp100(value)
	return math.max(0, math.min(100, value))
end

local function clamp01(value)
	return math.max(0, math.min(1, value))
end

-- saved: an optional table (from src/save.lua) to resume from. All fields
-- live on the same internal `now` clock, which only advances while the app
-- is open - so resuming from a save is just picking that clock back up,
-- with no elapsed-time decay to compute (there deliberately isn't any yet).
function Gauges.new(saved)
	saved = saved or {}
	local self = setmetatable({}, Gauges)

	self.satiety = saved.satiety or 100
	self.cleanliness = saved.cleanliness or 100
	self.petBuffExpiresAt = saved.petBuffExpiresAt or 0
	self.droppings = saved.droppings or {}
	self.cyclesSincePoop = saved.cyclesSincePoop or 0
	self.poopClockAccumulator = saved.poopClockAccumulator or 0
	self.lastAteAt = saved.lastAteAt or -math.huge
	self.lastLayAt = saved.lastLayAt or -math.huge
	self.layClockAccumulator = saved.layClockAccumulator or 0
	self.now = saved.now or 0

	self.isEating = false

	return self
end

function Gauges:setEating(isEating)
	self.isEating = isEating
end

function Gauges:isHungry()
	return self.satiety < EAT_ENTER_THRESHOLD
end

function Gauges:isFull()
	return self.satiety >= EAT_EXIT_THRESHOLD
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

-- Gates on happiness and refractory period, then rolls a chance that rises
-- with both happiness and time since the last lay. On success, records the
-- new lastLayAt (also closing the refractory gate for any other roll later
-- in the same update() call, so a burst of intervals can produce at most
-- one lay).
local function rollLayClock(self)
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
		self.lastLayAt = self.now
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

-- Advances the simulation by dt real seconds (scaled by the debug time
-- scale). Returns any dropping records newly spawned this call, so the
-- caller can create their visuals.
function Gauges:update(dt, timeScale, chickenX, chickenY)
	local scaledDt = math.min(dt, MAX_RAW_DT) * (timeScale or 1)
	self.now = self.now + scaledDt

	local satietyRate = self.isEating and SATIETY_EAT_RATE or -SATIETY_DECAY_RATE
	self.satiety = clamp100(self.satiety + satietyRate * scaledDt)
	if self.isEating then
		self.lastAteAt = self.now
	end

	local dirtyItemCount = #self.droppings + Coop.getFloorEggCount()
	local target = clamp100(100 - dirtyItemCount * CLEAN_PENALTY_PER_DROPPING)
	self.cleanliness = self.cleanliness + (target - self.cleanliness) * CLEAN_EASE_RATE * scaledDt

	local spawned = {}
	self.poopClockAccumulator = self.poopClockAccumulator + scaledDt
	while self.poopClockAccumulator >= POOP_CLOCK_INTERVAL do
		self.poopClockAccumulator = self.poopClockAccumulator - POOP_CLOCK_INTERVAL
		if rollPoopClock(self) then
			local x, y = jitteredPosition(chickenX, chickenY)
			local record = { x = x, y = y, createdAt = self.now }
			table.insert(self.droppings, record)
			table.insert(spawned, record)
		end
	end

	local laid = false
	self.layClockAccumulator = self.layClockAccumulator + scaledDt
	while self.layClockAccumulator >= LAY_CLOCK_INTERVAL do
		self.layClockAccumulator = self.layClockAccumulator - LAY_CLOCK_INTERVAL
		if rollLayClock(self) then
			laid = true
		end
	end

	return spawned, laid
end

function Gauges:removeDropping(record)
	for index, dropping in ipairs(self.droppings) do
		if dropping == record then
			table.remove(self.droppings, index)
			return
		end
	end
end

function Gauges:applyPetBuff()
	self.petBuffExpiresAt = self.now + PET_BUFF_DURATION
end

function Gauges:isPetBuffActive()
	return self.now < self.petBuffExpiresAt
end

function Gauges:getHappiness()
	local satiety, cleanliness = self.satiety, self.cleanliness
	local weightSatiety = (100 - satiety) + HAPPINESS_K
	local weightCleanliness = (100 - cleanliness) + HAPPINESS_K
	local base = (weightSatiety * satiety + weightCleanliness * cleanliness) / (weightSatiety + weightCleanliness)

	local petBuff = self:isPetBuffActive() and PET_BUFF_AMOUNT or 0
	return clamp100(base + petBuff)
end

function Gauges:getSaveData()
	return {
		satiety = self.satiety,
		cleanliness = self.cleanliness,
		petBuffExpiresAt = self.petBuffExpiresAt,
		droppings = self.droppings,
		cyclesSincePoop = self.cyclesSincePoop,
		poopClockAccumulator = self.poopClockAccumulator,
		lastAteAt = self.lastAteAt,
		lastLayAt = self.lastLayAt,
		layClockAccumulator = self.layClockAccumulator,
		now = self.now,
	}
end

return Gauges
