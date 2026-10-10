local Tuning = require("src.systems.tuning")
local Placement = require("src.systems.placement")
local SeedPatch = require("src.objects.items.seed_patch")
local Lettuce = require("src.objects.items.lettuce")

-- The shared owner of every placed food source: seed patches and lettuce
-- (CONTEXT.md's "Feed"). Owned by Garden alongside Treats (ADR-0018); stays
-- the one place a hungry chicken asks what there is to eat.
local Feed = {}

-- A source at or below this many units counts as empty, so float rounding
-- can't leave a near-invisible pile behind.
local EMPTY_EPSILON = 1e-6

local items = {}
Placement.register(function()
	return items
end)
local onSave = nil

local function save()
	if onSave then
		onSave()
	end
end

function Feed.setSaveCallback(fn)
	onSave = fn
end

local function distanceSquared(ax, ay, bx, by)
	local dx, dy = ax - bx, ay - by
	return dx * dx + dy * dy
end

local function removeItem(item)
	for index, existing in ipairs(items) do
		if existing == item then
			table.remove(items, index)
			break
		end
	end
	item.removed = true
	if item.destroyView then
		item.destroyView()
	end
end

-- Debits a source by the satiety delivered, converted to food units. Returns
-- false once fully depleted and removed.
function Feed.deplete(item, satietyDelivered)
	if item.removed then
		return false
	end
	item.remaining = math.max(0, item.remaining - satietyDelivered / Tuning.SATIETY_PER_UNIT)
	if item.updateVisual then
		item.updateVisual()
	end
	if item.remaining <= EMPTY_EPSILON then
		removeItem(item)
		save()
		return false
	end
	return true
end

-- Whether a food source exists anywhere - treats live in Treats, so an
-- unreachable mealworm can never suppress foraging.
function Feed.hasFoodSource()
	return #items > 0
end

-- Nearest food source to (x, y). Sources aren't exclusively claimed.
function Feed.findNearestSource(x, y)
	local nearest, nearestDistance = nil, nil
	for _, item in ipairs(items) do
		if item.kind == "source" then
			local distance = distanceSquared(x, y, item.x, item.y)
			if not nearestDistance or distance < nearestDistance then
				nearest, nearestDistance = item, distance
			end
		end
	end
	return nearest
end

-- Total food units left across every food source - offline catch-up's
-- food pool (ADR-0016).
function Feed.getTotalUnits()
	local total = 0
	for _, item in ipairs(items) do
		if item.kind == "source" then
			total = total + item.remaining
		end
	end
	return total
end

-- Drains `units` oldest-first (list order is placement order), removing any
-- that empty. Doesn't save - catch-up saves once at the end.
function Feed.drainOldest(units)
	local index = 1
	while units > 0 and index <= #items do
		local item = items[index]
		if item.kind == "source" then
			local taken = math.min(units, item.remaining)
			units = units - taken
			item.remaining = item.remaining - taken
			if item.remaining <= EMPTY_EPSILON then
				removeItem(item)
			else
				if item.updateVisual then
					item.updateVisual()
				end
				index = index + 1
			end
		else
			index = index + 1
		end
	end
end

local function createSeedPatch(x, y, remaining, offsets, placedAt)
	local item = {
		placedAt = placedAt,
		kind = "source",
		type = "seed",
		x = x,
		y = y,
		width = SeedPatch.WIDTH,
		height = SeedPatch.HEIGHT,
		capacity = SeedPatch.CAPACITY,
		remaining = remaining,
		offsets = offsets,
		removed = false,
	}
	SeedPatch.new(item)
	return item
end

function Feed.placeSeedPatch(x, y)
	local finalX, finalY = Placement.compute(SeedPatch.WIDTH, SeedPatch.HEIGHT, x, y)
	if not finalX then
		return
	end
	local item = createSeedPatch(finalX, finalY, SeedPatch.CAPACITY, SeedPatch.scatterOffsets(), os.time())
	table.insert(items, item)
	save()
	return item
end

local function createLettuceItem(x, y, remaining, placedAt)
	local item = {
		placedAt = placedAt,
		kind = "source",
		type = "lettuce",
		x = x,
		y = y,
		width = Lettuce.WIDTH,
		height = Lettuce.HEIGHT,
		capacity = Lettuce.CAPACITY,
		remaining = remaining,
		removed = false,
	}
	Lettuce.new(item)
	return item
end

function Feed.placeLettuce(x, y)
	local finalX, finalY = Placement.compute(Lettuce.WIDTH, Lettuce.HEIGHT, x, y)
	if not finalX then
		return
	end
	local item = createLettuceItem(finalX, finalY, Lettuce.CAPACITY, os.time())
	table.insert(items, item)
	save()
	return item
end

-- Dispatches a toolbar-driven placement by item type - Garden.tryPlace
-- delegates here for every food type. Returns true/false, matching what
-- toolbar.lua needs at drop time.
function Feed.tryPlace(itemType, x, y)
	if itemType == "seed_patch" then
		return Feed.placeSeedPatch(x, y) ~= nil
	elseif itemType == "lettuce" then
		return Feed.placeLettuce(x, y) ~= nil
	end
	return false
end

function Feed.getSaveData()
	local savedSources = {}
	for _, item in ipairs(items) do
		table.insert(savedSources, {
			type = item.type,
			x = item.x,
			y = item.y,
			remaining = item.remaining,
			offsets = item.offsets,
			placedAt = item.placedAt,
		})
	end
	return { sources = savedSources }
end

-- saved: the "feed" section of src/systems/save.lua's file, a sibling to
-- Garden's own section. Legacy saved.treats are migrated by Treats.load.
function Feed.load(saved)
	saved = saved or {}
	items = {}

	for _, savedSource in ipairs(saved.sources or {}) do
		local item
		if savedSource.type == "lettuce" then
			item = createLettuceItem(savedSource.x, savedSource.y, savedSource.remaining, savedSource.placedAt)
		else
			item = createSeedPatch(
				savedSource.x, savedSource.y, savedSource.remaining, savedSource.offsets, savedSource.placedAt
			)
		end
		table.insert(items, item)
	end
end

return Feed
