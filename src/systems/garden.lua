local YSort = require("src.systems.y_sort")
local Island = require("src.systems.island")
local Clock = require("src.systems.clock")
local Save = require("src.systems.save")
local Feed = require("src.systems.feed")
local Chicken = require("src.objects.chicken.chicken")
local Bed = require("src.objects.items.bed")
local Egg = require("src.objects.items.egg")
local Dropping = require("src.objects.items.dropping")

-- The single shared owner of every chicken, hen bed, egg, and dropping in
-- the garden, plus the player's collected-egg count, with Feed held
-- alongside it for the food side (CONTEXT.md's "Garden"). A hen's Gauges
-- (its lay clock) decides WHEN she lays; this module decides WHERE the
-- resulting egg goes and whose cleanliness a dropping counts against, since
-- beds/eggs/droppings belong to the garden as a whole, not to any one hen
-- (ADR-0007).
local Garden = {}

-- World points; scatters a floor egg around the bed it overflowed from, the
-- same idea as a dropping's own jitter.
local FLOOR_EGG_JITTER_RADIUS = 12

local chickens = {} -- array of Chicken instances
local beds = {} -- { view, x, y, egg }
local eggs = {} -- { view, bed (nil for a floor egg), x, y }
local droppings = {} -- array of Dropping view instances (each carries its own .record)
local collectedCount = 0
local lastFrameTime = nil

local function distanceSquared(ax, ay, bx, by)
	local dx, dy = ax - bx, ay - by
	return dx * dx + dy * dy
end

local function jitteredPosition(x, y)
	local angle = math.random() * math.pi * 2
	local radius = math.random() * FLOOR_EGG_JITTER_RADIUS
	return x + math.cos(angle) * radius, y + math.sin(angle) * radius
end

local function findNearestBed(x, y, requireOpen)
	local nearest, nearestDistance = nil, nil
	for _, bed in ipairs(beds) do
		if not requireOpen or not bed.egg then
			local distance = distanceSquared(x, y, bed.x, bed.y)
			if not nearestDistance or distance < nearestDistance then
				nearest, nearestDistance = bed, distance
			end
		end
	end
	return nearest
end

-- Folds into the cleanliness target the same way droppings do (ADR-0004) -
-- only floor eggs are dirty; eggs sitting in a bed are tidy.
local function getFloorEggCount()
	local count = 0
	for _, egg in ipairs(eggs) do
		if not egg.bed then
			count = count + 1
		end
	end
	return count
end

-- The single save entry point - builds the full save file and writes it.
-- Wired as Feed's own save callback too (see Garden.load), so a food-side
-- mutation saves through here as well.
function Garden.save()
	Save.write({
		garden = Garden.getSaveData(),
		feed = Feed.getSaveData(),
	})
end

function Garden.getCollectedCount()
	return collectedCount
end

-- The garden-wide dirty-item count every chicken's cleanliness gauge eases
-- toward (CONTEXT.md's Cleanliness, extended so a dropping counts against
-- every chicken sharing the garden, not just the one that made it).
function Garden.getDirtyItemCount()
	return #droppings + getFloorEggCount()
end

local function insertDropping(record)
	local view = Dropping.new(record, function(droppingView)
		Garden.removeDropping(droppingView)
	end)
	table.insert(droppings, view)
end

function Garden.addDropping(record)
	insertDropping(record)
	Garden.save()
end

function Garden.removeDropping(view)
	for index, existing in ipairs(droppings) do
		if existing == view then
			table.remove(droppings, index)
			break
		end
	end
	view:destroy()
	Garden.save()
end

local function createBedView(bed)
	return Bed.new(bed, function()
		Garden.save()
	end)
end

function Garden.placeBed(x, y)
	local bed = { x = x, y = y, egg = nil }
	bed.view = createBedView(bed)
	table.insert(beds, bed)
	Garden.save()
	return bed
end

local function attachEggToBed(bed)
	local egg = { bed = bed }
	egg.view = Egg.newInBed(bed.view, function()
		Garden.collectEgg(egg)
	end)
	bed.egg = egg
	table.insert(eggs, egg)
	return egg
end

local function createFloorEgg(x, y)
	local egg = { bed = nil, x = x, y = y }
	egg.view = Egg.newFloor(x, y, function()
		Garden.collectEgg(egg)
	end)
	table.insert(eggs, egg)
	return egg
end

-- Called by a hen's Gauges (via Chicken:update's return value) when its lay
-- clock fires. x, y is the hen's position at the moment of laying.
-- Placement priority: nearest open bed, else near the closest bed (all
-- occupied), else a random spot in the play area (no beds at all).
function Garden.hatchEgg(x, y)
	local openBed = findNearestBed(x, y, true)
	if openBed then
		attachEggToBed(openBed)
		Garden.save()
		return
	end

	local closestBed = findNearestBed(x, y, false)
	local eggX, eggY
	if closestBed then
		eggX, eggY = jitteredPosition(closestBed.x, closestBed.y)
	else
		local bounds = Island.getInnerBounds()
		eggX = bounds.minX + math.random() * (bounds.maxX - bounds.minX)
		eggY = bounds.minY + math.random() * (bounds.maxY - bounds.minY)
	end

	createFloorEgg(eggX, eggY)
	Garden.save()
end

-- Removes an egg (in a bed or on the floor), frees its bed if it had one,
-- and credits the player's stash. Shared by a direct tap and any future
-- collect-all affordance.
function Garden.collectEgg(egg)
	for index, existing in ipairs(eggs) do
		if existing == egg then
			table.remove(eggs, index)
			break
		end
	end

	if egg.bed then
		egg.bed.egg = nil
		egg.view:removeSelf()
	else
		YSort.remove(egg.view)
		egg.view:removeSelf()
	end

	collectedCount = collectedCount + 1
	Garden.save()
end

-- The toolbar's single placement entry point, dispatched by item type -
-- validity-checking and placement-commit both happen here (or, for food
-- types, inside Feed), never in the item's own file. Returns true/false.
function Garden.tryPlace(itemType, x, y)
	if itemType == "bed" then
		if not Bed.isValidPosition(x, y) then
			return false
		end
		Garden.placeBed(x, y)
		return true
	end
	return Feed.tryPlace(itemType, x, y)
end

local function onFrame(event)
	if not lastFrameTime then
		lastFrameTime = event.time
		return
	end
	local rawDt = (event.time - lastFrameTime) / 1000
	lastFrameTime = event.time

	Clock.advance(rawDt)
	local dirtyItemCount = Garden.getDirtyItemCount()

	for _, chicken in ipairs(chickens) do
		local spawned, laid = chicken:update(Clock.getDt(), dirtyItemCount)
		for _, record in ipairs(spawned) do
			Garden.addDropping(record)
		end
		if laid then
			Garden.hatchEgg(chicken:getPosition())
		end
	end
end

function Garden.getSaveData()
	local savedBeds = {}
	local bedIndex = {}
	for i, bed in ipairs(beds) do
		savedBeds[i] = { x = bed.x, y = bed.y }
		bedIndex[bed] = i
	end

	local savedEggs = {}
	for i, egg in ipairs(eggs) do
		savedEggs[i] = {
			x = egg.bed and egg.bed.x or egg.x,
			y = egg.bed and egg.bed.y or egg.y,
			bedIndex = egg.bed and bedIndex[egg.bed] or nil,
		}
	end

	local savedDroppings = {}
	for i, view in ipairs(droppings) do
		savedDroppings[i] = { x = view.record.x, y = view.record.y, createdAt = view.record.createdAt }
	end

	local savedChickens = {}
	for i, chicken in ipairs(chickens) do
		savedChickens[i] = chicken:getSaveData()
	end

	return {
		collectedCount = collectedCount,
		beds = savedBeds,
		eggs = savedEggs,
		droppings = savedDroppings,
		chickens = savedChickens,
	}
end

-- saved: the full save file from src/systems/save.lua ({ garden = ..., feed
-- = ... }). Loads Feed first (so its items are visible on the first
-- decide), then this module's own beds/eggs/droppings/chickens. Spawns
-- exactly one chicken today regardless of how many are saved - the
-- chickens array/save shape is ready for more, but nothing yet creates a
-- second one (a small follow-up, not part of this refactor).
function Garden.load(saved)
	saved = saved or {}
	local savedGarden = saved.garden or {}

	Feed.load(saved.feed)
	Feed.setSaveCallback(Garden.save)

	collectedCount = savedGarden.collectedCount or 0
	beds = {}
	eggs = {}
	droppings = {}
	chickens = {}

	for _, savedBed in ipairs(savedGarden.beds or {}) do
		local bed = { x = savedBed.x, y = savedBed.y, egg = nil }
		bed.view = createBedView(bed)
		table.insert(beds, bed)
	end

	for _, savedEgg in ipairs(savedGarden.eggs or {}) do
		local bed = savedEgg.bedIndex and beds[savedEgg.bedIndex]
		if bed then
			attachEggToBed(bed)
		else
			createFloorEgg(savedEgg.x, savedEgg.y)
		end
	end

	for _, savedDropping in ipairs(savedGarden.droppings or {}) do
		insertDropping({ x = savedDropping.x, y = savedDropping.y, createdAt = savedDropping.createdAt })
	end

	local savedChickenData = (savedGarden.chickens and savedGarden.chickens[1]) or nil
	table.insert(chickens, Chicken.new(savedChickenData))

	Runtime:addEventListener("enterFrame", onFrame)
end

return Garden
