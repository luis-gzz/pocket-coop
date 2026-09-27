local Constants = require("src.util.constants")
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
-- (ADR-0007); the hen's own nest state carries out the walk there (ADR-0013).
local Garden = {}

-- The radius (CONTEXT.md's Egg slot) a hen picks a floor spot within when
-- every bed is full, so an overflow egg still lands near a bed rather than
-- anywhere on the island.
local FLOOR_LAY_RADIUS = 3 * Constants.TILE_SIZE

local chickens = {} -- array of Chicken instances
local beds = {} -- { view, x, y, eggs = { [1..Bed.SLOT_COUNT] = egg or nil } }
local eggs = {} -- { view, bed (nil for a floor egg), slot (only set if bed), x, y }
local droppings = {} -- array of Dropping view instances (each carries its own .record)
local collectedCount = 0
local lastFrameTime = nil

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function distanceSquared(ax, ay, bx, by)
	local dx, dy = ax - bx, ay - by
	return dx * dx + dy * dy
end

-- A random point within radius of (x, y) - used for the floor-near-bed spot
-- a hen picks when every bed is full.
local function randomPointNear(x, y, radius)
	local angle = math.random() * math.pi * 2
	local distance = math.random() * radius
	return x + math.cos(angle) * distance, y + math.sin(angle) * distance
end

local function clampToIsland(x, y, width, height)
	local bounds = Island.getInnerBounds()
	return clamp(x, bounds.minX + width / 2, bounds.maxX - width / 2),
		clamp(y, bounds.minY + height / 2, bounds.maxY - height / 2)
end

local function countBedEggs(bed)
	local count = 0
	for i = 1, Bed.SLOT_COUNT do
		if bed.eggs[i] then
			count = count + 1
		end
	end
	return count
end

local function findOpenSlot(bed)
	for i = 1, Bed.SLOT_COUNT do
		if not bed.eggs[i] then
			return i
		end
	end
	return nil
end

local function findNearestBed(x, y, requireOpen)
	local nearest, nearestDistance = nil, nil
	for _, bed in ipairs(beds) do
		if not requireOpen or countBedEggs(bed) < Bed.SLOT_COUNT then
			local distance = distanceSquared(x, y, bed.x, bed.y)
			if not nearestDistance or distance < nearestDistance then
				nearest, nearestDistance = bed, distance
			end
		end
	end
	return nearest
end

-- Whether (x, y) sits within another bed's half-width AND half-height at
-- once - the "directly on top of each other" zone ADR-0014 pushes a
-- placement or drag out of. exclude skips a bed re-checking itself mid-drag.
local function overlapsAnotherBed(x, y, exclude)
	for _, bed in ipairs(beds) do
		if bed ~= exclude and math.abs(x - bed.x) < Bed.WIDTH / 2 and math.abs(y - bed.y) < Bed.HEIGHT / 2 then
			return bed
		end
	end
	return nil
end

-- Pushes (x, y) out along its offset from `other`'s center by just enough to
-- clear the half-width/half-height zone on whichever axis needs the smaller
-- push, so the bed lands as close as the rule allows rather than
-- overcorrecting (ADR-0014). A perfectly coincident pair picks a random
-- direction, since there's no offset to push along.
local function separateFromBed(x, y, other)
	local dx, dy = x - other.x, y - other.y
	if dx == 0 and dy == 0 then
		local angle = math.random() * math.pi * 2
		dx, dy = math.cos(angle), math.sin(angle)
	end

	local pushX = Bed.WIDTH / 2 - math.abs(dx)
	local pushY = Bed.HEIGHT / 2 - math.abs(dy)

	if pushX <= pushY then
		local sign = (dx > 0) and 1 or (dx < 0) and -1 or ((math.random() < 0.5) and 1 or -1)
		return other.x + sign * (Bed.WIDTH / 2), y
	end

	local sign = (dy > 0) and 1 or (dy < 0) and -1 or ((math.random() < 0.5) and 1 or -1)
	return x, other.y + sign * (Bed.HEIGHT / 2)
end

-- Resolves a bed placement or drag to its final (x, y): rejects outright if
-- it would leave the play area (nil, nil), otherwise nudges out of another
-- bed's overlap zone if needed and re-clamps into the island (ADR-0014).
-- exclude is the bed's own record when repositioning an existing one.
function Garden.resolveBedPlacement(x, y, exclude)
	if not Bed.isValidPosition(x, y) then
		return nil, nil
	end

	local overlapping = overlapsAnotherBed(x, y, exclude)
	if overlapping then
		x, y = separateFromBed(x, y, overlapping)
		x, y = clampToIsland(x, y, Bed.WIDTH, Bed.HEIGHT)
	end

	return x, y
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
	end, function(x, y)
		return Garden.resolveBedPlacement(x, y, bed)
	end)
end

function Garden.placeBed(x, y)
	local bed = { x = x, y = y, eggs = {} }
	bed.view = createBedView(bed)
	table.insert(beds, bed)
	Garden.save()
	return bed
end

local function attachEggToBed(bed)
	local slot = findOpenSlot(bed)
	local egg = { bed = bed, slot = slot }
	egg.view = Egg.newInBed(bed.view, Bed.getSlotOffsetX(slot), function()
		Garden.collectEgg(egg)
	end)
	bed.eggs[slot] = egg
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

-- Decides where a hen headed to lay should walk, and what it'll do once it
-- gets there (CONTEXT.md's Nest state) - called once when the lay clock
-- fires, and again on arrival if the chosen bed filled up in the meantime.
-- Priority: nearest bed with an open slot: else a floor spot within
-- FLOOR_LAY_RADIUS of the nearest bed (every one full); else "immediate"
-- (no beds exist anywhere - the hen lays right where it stands, ADR-0013).
function Garden.pickLayTarget(x, y)
	local openBed = findNearestBed(x, y, true)
	if openBed then
		return { kind = "bed", bed = openBed }
	end

	local closestBed = findNearestBed(x, y, false)
	if closestBed then
		local floorX, floorY = randomPointNear(closestBed.x, closestBed.y, FLOOR_LAY_RADIUS)
		floorX, floorY = clampToIsland(floorX, floorY, Egg.WIDTH, Egg.HEIGHT)
		return { kind = "floor", x = floorX, y = floorY }
	end

	return { kind = "immediate" }
end

-- Called by a hen's nest state once it reaches its target (or immediately,
-- for the "immediate" no-beds-anywhere case, via x/y = the hen's current
-- position). Returns false only when a "bed" target filled up since it was
-- picked, so the hen can ask Garden.pickLayTarget again instead of laying
-- somewhere stale.
function Garden.commitLay(target, x, y)
	if target.kind == "bed" then
		if not findOpenSlot(target.bed) then
			return false
		end
		attachEggToBed(target.bed)
		Garden.save()
		return true
	end

	createFloorEgg(x, y)
	Garden.save()
	return true
end

-- Removes an egg (in a bed or on the floor), frees its slot if it had one,
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
		egg.bed.eggs[egg.slot] = nil
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
		local finalX, finalY = Garden.resolveBedPlacement(x, y)
		if not finalX then
			return false
		end
		Garden.placeBed(finalX, finalY)
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
			chicken:beginNesting(Garden.pickLayTarget(chicken:getPosition()))
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
		local bed = { x = savedBed.x, y = savedBed.y, eggs = {} }
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
	table.insert(chickens, Chicken.new(savedChickenData, {
		pickLayTarget = Garden.pickLayTarget,
		commitLay = Garden.commitLay,
	}))

	Runtime:addEventListener("enterFrame", onFrame)
end

return Garden
