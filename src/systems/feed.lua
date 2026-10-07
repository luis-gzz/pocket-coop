local Constants = require("src.util.constants")
local Layout = require("src.ui.layout")
local Tuning = require("src.systems.tuning")
local SeedPatch = require("src.objects.items.seed_patch")
local Lettuce = require("src.objects.items.lettuce")
local Mealworm = require("src.objects.items.mealworm")

-- The shared owner of every placed food item: seed patches, lettuce, and
-- mealworm (CONTEXT.md's "Feed"). Owned by Garden alongside its bed/egg/
-- dropping state; stays the one place a hungry chicken asks what there is
-- to eat.
local Feed = {}

-- A treat alerts the nearest chicken within this radius, re-checked every
-- frame.
local TREAT_ALERT_RADIUS = 48 * Constants.PIXEL_SCALE

-- Placing a food item within this distance of another's center just nudges
-- it a little, rather than blocking the placement - purely so two items
-- don't render right on top of each other. A center-to-center distance
-- rather than a footprint overlap, so it doesn't depend on either item's
-- own box size.
local OVERLAP_TRIGGER_DISTANCE = Constants.TILE_SIZE / 2
-- About a tile, so the nudge itself is actually visible.
local OVERLAP_JITTER_RADIUS = Constants.TILE_SIZE

-- A source at or below this many units counts as empty, so float rounding
-- can't leave a near-invisible pile behind.
local EMPTY_EPSILON = 1e-6

-- Every placed food item (sources and treats) lives in this one list.
local items = {}
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

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function isWithinPlayArea(x, y, width, height)
	local bounds = Layout.getPlayArea()
	return x - width / 2 >= bounds.minX
		and x + width / 2 <= bounds.maxX
		and y - height / 2 >= bounds.minY
		and y + height / 2 <= bounds.maxY
end

-- Clamps (x, y) so a width x height footprint stays fully within the play area.
local function clampToPlayArea(x, y, width, height)
	local bounds = Layout.getPlayArea()
	return clamp(x, bounds.minX + width / 2, bounds.maxX - width / 2),
		clamp(y, bounds.minY + height / 2, bounds.maxY - height / 2)
end

local function findNearbyItem(x, y, exclude)
	for _, item in ipairs(items) do
		if item ~= exclude and distanceSquared(x, y, item.x, item.y) < OVERLAP_TRIGGER_DISTANCE * OVERLAP_TRIGGER_DISTANCE then
			return item
		end
	end
	return nil
end

-- Rejects a drop outside the play area; otherwise always succeeds, nudging a
-- little (clamped back into the play area) if it lands too close to another
-- food item's center.
local function computePlacement(width, height, x, y, exclude)
	if not isWithinPlayArea(x, y, width, height) then
		return nil, nil
	end

	if findNearbyItem(x, y, exclude) then
		local angle = math.random() * math.pi * 2
		local distance = math.random() * OVERLAP_JITTER_RADIUS
		x, y = clampToPlayArea(x + math.cos(angle) * distance, y + math.sin(angle) * distance, width, height)
	end

	return x, y
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

-- Whether a food source exists anywhere - blind to treats, so an
-- unreachable mealworm can never suppress foraging.
function Feed.hasFoodSource()
	for _, item in ipairs(items) do
		if item.kind == "source" then
			return true
		end
	end
	return false
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

-- Claims the nearest treat within TREAT_ALERT_RADIUS of (x, y) that's
-- unclaimed (and not mid-drag) or already `chicken`'s own, or returns nil.
function Feed.claimTreatNear(chicken, x, y)
	local nearest, nearestDistance = nil, nil
	for _, item in ipairs(items) do
		if item.kind == "treat" and not item.dragging and (not item.claimedBy or item.claimedBy == chicken) then
			local distance = distanceSquared(x, y, item.x, item.y)
			if distance <= TREAT_ALERT_RADIUS * TREAT_ALERT_RADIUS then
				if not nearestDistance or distance < nearestDistance then
					nearest, nearestDistance = item, distance
				end
			end
		end
	end
	if nearest then
		nearest.claimedBy = chicken
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

-- Frees a treat's claim without consuming it.
function Feed.releaseTreatClaim(item)
	if item and item.kind == "treat" and not item.removed then
		item.claimedBy = nil
	end
end

-- Removes a treat instantly; the satiety/happiness payoff is applied by
-- the caller.
function Feed.consumeTreat(item)
	removeItem(item)
	save()
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
	local finalX, finalY = computePlacement(SeedPatch.WIDTH, SeedPatch.HEIGHT, x, y)
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
	local finalX, finalY = computePlacement(Lettuce.WIDTH, Lettuce.HEIGHT, x, y)
	if not finalX then
		return
	end
	local item = createLettuceItem(finalX, finalY, Lettuce.CAPACITY, os.time())
	table.insert(items, item)
	save()
	return item
end

local function createMealwormItem(x, y)
	local item = {
		kind = "treat",
		type = "mealworm",
		fullness = Mealworm.FULLNESS,
		x = x,
		y = y,
		width = Mealworm.WIDTH,
		height = Mealworm.HEIGHT,
		claimedBy = nil,
		removed = false,
	}
	Mealworm.new(item, function(dropX, dropY)
		local finalX, finalY = computePlacement(Mealworm.WIDTH, Mealworm.HEIGHT, dropX, dropY, item)
		if finalX then
			-- item.x/y so a save taken right now (or immediately after, before
			-- mealworm.lua's own moveTo redundantly re-applies the same
			-- values) reflects the committed position, not the pre-drag one.
			item.x, item.y = finalX, finalY
			save()
		end
		return finalX, finalY
	end)
	return item
end

function Feed.placeMealworm(x, y)
	local finalX, finalY = computePlacement(Mealworm.WIDTH, Mealworm.HEIGHT, x, y)
	if not finalX then
		return
	end
	local item = createMealwormItem(finalX, finalY)
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
	elseif itemType == "mealworm" then
		return Feed.placeMealworm(x, y) ~= nil
	end
	return false
end

function Feed.getSaveData()
	local savedSources = {}
	local savedTreats = {}
	for _, item in ipairs(items) do
		if item.kind == "source" then
			table.insert(savedSources, {
				type = item.type,
				x = item.x,
				y = item.y,
				remaining = item.remaining,
				offsets = item.offsets,
				placedAt = item.placedAt,
			})
		else
			table.insert(savedTreats, { x = item.x, y = item.y })
		end
	end
	return { sources = savedSources, treats = savedTreats }
end

-- saved: the "feed" section of src/systems/save.lua's file, a sibling to
-- Garden's own section.
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

	for _, savedTreat in ipairs(saved.treats or {}) do
		table.insert(items, createMealwormItem(savedTreat.x, savedTreat.y))
	end
end

return Feed
