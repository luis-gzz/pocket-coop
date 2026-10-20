local Tuning = require("src.systems.tuning")
local Fixtures = require("src.systems.fixtures")
local WaterBowl = require("src.objects.items.water_bowl")

-- The shared owner of every water bowl (CONTEXT.md's Water bowl), Feed's
-- counterpart for water. Owned by Garden alongside Feed and Treats.
local Bowls = {}

-- A bowl at or below this much water counts as empty, so float rounding
-- can't leave it drinkable forever.
local EMPTY_EPSILON = 1e-6

local bowls = {}
Fixtures.register(function()
	return bowls
end)
local onSave = nil

local function save()
	if onSave then
		onSave()
	end
end

function Bowls.setSaveCallback(fn)
	onSave = fn
end

local function hasWater(bowl)
	return bowl.water > EMPTY_EPSILON
end

local function createBowl(x, y, water)
	local bowl = {
		kind = "bowl",
		x = x,
		y = y,
		width = WaterBowl.WIDTH,
		height = WaterBowl.HEIGHT,
		footprintShare = WaterBowl.FOOTPRINT_SHARE,
		capacity = Tuning.BOWL_WATER,
		water = water,
		dragging = false,
	}
	WaterBowl.new(bowl, function()
		Fixtures.notifyChanged()
		save()
	end, function(dropX, dropY)
		return Fixtures.resolve(dropX, dropY, bowl.width, bowl.height, bowl.footprintShare, bowl)
	end)
	return bowl
end

function Bowls.tryPlace(x, y)
	local finalX, finalY = Fixtures.resolve(x, y, WaterBowl.WIDTH, WaterBowl.HEIGHT, WaterBowl.FOOTPRINT_SHARE)
	if not finalX then
		return false
	end
	table.insert(bowls, createBowl(finalX, finalY, Tuning.BOWL_WATER))
	Fixtures.notifyChanged()
	save()
	return true
end

-- Whether any bowl a chicken could drink from right now holds water.
function Bowls.hasWater()
	for _, bowl in ipairs(bowls) do
		if not bowl.dragging and hasWater(bowl) then
			return true
		end
	end
	return false
end

-- Nearest bowl with water to (x, y), skipping one mid-drag.
function Bowls.findNearestWithWater(x, y)
	local nearest, nearestDistance = nil, nil
	for _, bowl in ipairs(bowls) do
		if not bowl.dragging and hasWater(bowl) then
			local dx, dy = x - bowl.x, y - bowl.y
			local distance = dx * dx + dy * dy
			if not nearestDistance or distance < nearestDistance then
				nearest, nearestDistance = bowl, distance
			end
		end
	end
	return nearest
end

-- Debits a bowl by the hydration drunk. Returns false once it's empty.
function Bowls.drain(bowl, amount)
	bowl.water = math.max(0, bowl.water - amount)
	if not hasWater(bowl) then
		bowl.water = 0
		bowl.updateVisual()
		save()
		return false
	end
	bowl.updateVisual() -- may cross into the half-full sprite
	return true
end

-- The bucket: fills the bowl under (x, y) to full. False (cancel) if
-- there's no bowl there or it's already full.
function Bowls.tryRefill(x, y)
	for _, bowl in ipairs(bowls) do
		if math.abs(x - bowl.x) <= bowl.width / 2 and math.abs(y - bowl.y) <= bowl.height / 2 then
			if bowl.water >= bowl.capacity - EMPTY_EPSILON then
				return false
			end
			bowl.water = bowl.capacity
			bowl.updateVisual()
			save()
			return true
		end
	end
	return false
end

-- Total water left across every bowl - offline catch-up's water pool.
function Bowls.getTotalWater()
	local total = 0
	for _, bowl in ipairs(bowls) do
		total = total + bowl.water
	end
	return total
end

-- Drains `amount` oldest-first. Doesn't save - catch-up saves once at the end.
function Bowls.drainOldest(amount)
	for _, bowl in ipairs(bowls) do
		if amount <= 0 then
			break
		end
		local taken = math.min(amount, bowl.water)
		amount = amount - taken
		bowl.water = bowl.water - taken
		if not hasWater(bowl) then
			bowl.water = 0
		end
		bowl.updateVisual()
	end
end

function Bowls.getSaveData()
	local saved = {}
	for _, bowl in ipairs(bowls) do
		table.insert(saved, { x = bowl.x, y = bowl.y, water = bowl.water })
	end
	return saved
end

-- saved: the "bowls" section of src/systems/save.lua's file.
function Bowls.load(saved)
	bowls = {}
	for _, savedBowl in ipairs(saved or {}) do
		table.insert(bowls, createBowl(savedBowl.x, savedBowl.y, savedBowl.water or Tuning.BOWL_WATER))
	end
end

return Bowls
