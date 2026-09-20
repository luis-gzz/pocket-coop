local Constants = require("src.constants")
local Island = require("src.island")
local YSort = require("src.y_sort")
local Wiggle = require("src.wiggle")
local Tooltip = require("src.tooltip")

-- The shared owner of every placed food item: seed patches, lettuce, and
-- mealworm. Sibling to src/coop.lua (ADR-0011).
local Feed = {}

-- Food sources hold a pool of fullness that eating draws down; one unit of
-- capacity is one point of satiety delivered.
local SEED_ICON_PATH = "assets/objects/seeds_icon.png"
local SEED_SPRITE_PATH = "assets/objects/seed.png"
local SEED_ICON_NATIVE_SIZE = 20 -- also the seed patch's collision/containment box
local SEED_SPRITE_NATIVE_SIZE = 2
local SEED_SCATTER_RADIUS_NATIVE = 10
local SEED_COUNT = 10
local SEED_CAPACITY = 100

local LETTUCE_PATH = "assets/objects/lettuce.png"
local LETTUCE_NATIVE_SIZE = 16
local LETTUCE_CAPACITY = 200
-- Lettuce visibly shrinks toward this floor as it's eaten down, rather than
-- vanishing all at once like the seed patch's scatter does.
local LETTUCE_MIN_SCALE = 0.4

local MEALWORM_PATH = "assets/objects/mealworm.png"
local MEALWORM_NATIVE_WIDTH, MEALWORM_NATIVE_HEIGHT = 12, 5

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

-- ms; matches src/chicken.lua's own long-press threshold.
local LONG_PRESS_TIME = 350
local WIGGLE_ANGLE = 8
local WIGGLE_STEP_TIME = 90

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

local function isWithinIsland(x, y, width, height)
	local bounds = Island.getInnerBounds()
	return x - width / 2 >= bounds.minX
		and x + width / 2 <= bounds.maxX
		and y - height / 2 >= bounds.minY
		and y + height / 2 <= bounds.maxY
end

-- Clamps (x, y) so a width x height footprint stays fully within the island.
local function clampToIsland(x, y, width, height)
	local bounds = Island.getInnerBounds()
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

-- Rejects a drop outside the island; otherwise always succeeds, nudging a
-- little (clamped back into the island) if it lands too close to another
-- food item's center.
local function computePlacement(width, height, x, y, exclude)
	if not isWithinIsland(x, y, width, height) then
		return nil, nil
	end

	if findNearbyItem(x, y, exclude) then
		local angle = math.random() * math.pi * 2
		local distance = math.random() * OVERLAP_JITTER_RADIUS
		x, y = clampToIsland(x + math.cos(angle) * distance, y + math.sin(angle) * distance, width, height)
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

-- Debits a source's remaining capacity by the satiety actually delivered.
-- Returns false once fully depleted and removed.
function Feed.deplete(item, amount)
	if item.removed then
		return false
	end
	item.remaining = math.max(0, item.remaining - amount)
	if item.updateVisual then
		item.updateVisual()
	end
	if item.remaining <= 0 then
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

-- Claims the nearest unclaimed treat within TREAT_ALERT_RADIUS of (x, y)
-- for `chicken`, or returns nil.
function Feed.claimTreatNear(chicken, x, y)
	local nearest, nearestDistance = nil, nil
	for _, item in ipairs(items) do
		if item.kind == "treat" and not item.claimedBy then
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

-- Seed patch: ten seed sprites scattered around its center, hiding one at
-- a time as it depletes. Not registered with YSort - always renders behind.
local function createSeedPatch(x, y, remaining, offsets)
	local group = display.newGroup()
	YSort.getGroup():insert(group)
	group.x, group.y = x, y

	local seedSize = SEED_SPRITE_NATIVE_SIZE * Constants.PIXEL_SCALE
	local seeds = {}
	for _, offset in ipairs(offsets) do
		local seed = display.newImageRect(group, SEED_SPRITE_PATH, seedSize, seedSize)
		seed.x = offset.dx
		seed.y = offset.dy
		table.insert(seeds, seed)
	end

	local item = {
		kind = "source",
		type = "seed",
		x = x,
		y = y,
		width = SEED_ICON_NATIVE_SIZE * Constants.PIXEL_SCALE,
		height = SEED_ICON_NATIVE_SIZE * Constants.PIXEL_SCALE,
		capacity = SEED_CAPACITY,
		remaining = remaining,
		offsets = offsets,
		removed = false,
	}

	function item.updateVisual()
		local fraction = item.remaining / item.capacity
		for index, seed in ipairs(seeds) do
			seed.isVisible = fraction > (index - 1) / SEED_COUNT
		end
	end
	item.updateVisual()

	function item.destroyView()
		group:removeSelf()
	end

	-- A hit target covering the whole patch, not just the tiny seed sprites.
	local hitArea = display.newRect(group, 0, 0, item.width, item.height)
	hitArea:setFillColor(0, 0, 0, 0.01)
	hitArea:addEventListener("tap", function()
		Tooltip.show({
			x = item.x,
			y = item.y,
			rows = {
				{ label = "Seed patch", getValue = function() return item.remaining / item.capacity * 100 end },
			},
		})
		return true
	end)

	return item
end

-- Scatters the ten seed sprites near the patch's center; generated once
-- and saved so a reload keeps the same arrangement.
local function scatterOffsets()
	local radius = SEED_SCATTER_RADIUS_NATIVE * Constants.PIXEL_SCALE
	local offsets = {}
	for _ = 1, SEED_COUNT do
		local angle = math.random() * math.pi * 2
		local distance = math.random() * radius
		table.insert(offsets, { dx = math.cos(angle) * distance, dy = math.sin(angle) * distance })
	end
	return offsets
end

function Feed.placeSeedPatch(x, y)
	local width = SEED_ICON_NATIVE_SIZE * Constants.PIXEL_SCALE
	local finalX, finalY = computePlacement(width, width, x, y)
	if not finalX then
		return
	end
	local item = createSeedPatch(finalX, finalY, SEED_CAPACITY, scatterOffsets())
	table.insert(items, item)
	save()
	return item
end

function Feed.isValidSeedPatchPosition(x, y)
	local width = SEED_ICON_NATIVE_SIZE * Constants.PIXEL_SCALE
	local finalX = computePlacement(width, width, x, y)
	return finalX ~= nil
end

-- Lettuce: a single sprite, anchored at its bottom edge so shrinking reads
-- as being eaten down. Not registered with YSort - always renders behind.
local function createLettuceItem(x, y, remaining)
	local width = LETTUCE_NATIVE_SIZE * Constants.PIXEL_SCALE
	local sprite = display.newImageRect(LETTUCE_PATH, width, width)
	YSort.getGroup():insert(sprite)
	sprite.anchorY = 1
	sprite.x = x
	sprite.y = y + width / 2

	local item = {
		kind = "source",
		type = "lettuce",
		x = x,
		y = y,
		width = width,
		height = width,
		capacity = LETTUCE_CAPACITY,
		remaining = remaining,
		removed = false,
	}

	function item.updateVisual()
		local fraction = item.remaining / item.capacity
		local scale = LETTUCE_MIN_SCALE + (1 - LETTUCE_MIN_SCALE) * fraction
		sprite.xScale = scale
		sprite.yScale = scale
	end
	item.updateVisual()

	function item.destroyView()
		sprite:removeSelf()
	end

	sprite:addEventListener("tap", function()
		Tooltip.show({
			x = item.x,
			y = item.y,
			rows = {
				{ label = "Lettuce", getValue = function() return item.remaining / item.capacity * 100 end },
			},
		})
		return true
	end)

	return item
end

function Feed.placeLettuce(x, y)
	local width = LETTUCE_NATIVE_SIZE * Constants.PIXEL_SCALE
	local finalX, finalY = computePlacement(width, width, x, y)
	if not finalX then
		return
	end
	local item = createLettuceItem(finalX, finalY, LETTUCE_CAPACITY)
	table.insert(items, item)
	save()
	return item
end

function Feed.isValidLettucePosition(x, y)
	local width = LETTUCE_NATIVE_SIZE * Constants.PIXEL_SCALE
	local finalX = computePlacement(width, width, x, y)
	return finalX ~= nil
end

-- Mealworm: the only draggable food item. Dragging it while claimed keeps
-- the claim and re-targets the chicken mid-walk.
local function attachTreatDrag(item, sprite)
	local width, height = item.width, item.height
	local pendingTouch = false
	local isDragging = false
	local longPressHandle = nil
	local originalX, originalY
	local dragOffsetX, dragOffsetY
	local wiggleHandle = nil

	local function beginDrag(startX, startY)
		isDragging = true
		originalX, originalY = item.x, item.y
		dragOffsetX = sprite.x - startX
		dragOffsetY = sprite.y - startY
		wiggleHandle = Wiggle.start(sprite, WIGGLE_ANGLE, WIGGLE_STEP_TIME, function()
			return isDragging
		end)
	end

	local function moveTo(x, y)
		sprite.x, sprite.y = x, y
		item.x, item.y = x, y
		if item.claimedBy and item.claimedBy.retargetApproach then
			item.claimedBy:retargetApproach()
		end
	end

	local function onTouch(event)
		if event.phase == "began" then
			display.getCurrentStage():setFocus(sprite, event.id)
			sprite.isFocus = true
			pendingTouch = true
			local startX, startY = event.x, event.y
			longPressHandle = timer.performWithDelay(LONG_PRESS_TIME, function()
				longPressHandle = nil
				if pendingTouch then
					beginDrag(startX, startY)
					pendingTouch = false
				end
			end)
		elseif sprite.isFocus then
			if event.phase == "moved" then
				if isDragging then
					moveTo(event.x + dragOffsetX, event.y + dragOffsetY)
				end
			elseif event.phase == "ended" or event.phase == "cancelled" then
				display.getCurrentStage():setFocus(sprite, nil)
				sprite.isFocus = false

				if longPressHandle then
					timer.cancel(longPressHandle)
					longPressHandle = nil
				end
				pendingTouch = false

				if isDragging then
					isDragging = false
					Wiggle.stop(wiggleHandle)
					wiggleHandle = nil
					local finalX, finalY
					if event.phase == "ended" then
						finalX, finalY = computePlacement(width, height, sprite.x, sprite.y, item)
					end
					if finalX then
						moveTo(finalX, finalY)
						save()
					else
						transition.to(sprite, {
							x = originalX,
							y = originalY,
							time = 150,
							onComplete = function()
								moveTo(originalX, originalY)
							end,
						})
					end
				end
			end
		end
		return true
	end
	sprite:addEventListener("touch", onTouch)
end

local function createMealwormItem(x, y)
	local width = MEALWORM_NATIVE_WIDTH * Constants.PIXEL_SCALE
	local height = MEALWORM_NATIVE_HEIGHT * Constants.PIXEL_SCALE
	local sprite = display.newImageRect(MEALWORM_PATH, width, height)
	YSort.getGroup():insert(sprite)
	sprite.x = x
	sprite.y = y
	YSort.add(sprite, function(view)
		return view.y + height / 2
	end)

	local item = {
		kind = "treat",
		type = "mealworm",
		x = x,
		y = y,
		width = width,
		height = height,
		claimedBy = nil,
		removed = false,
	}

	function item.destroyView()
		YSort.remove(sprite)
		sprite:removeSelf()
	end

	attachTreatDrag(item, sprite)

	return item
end

function Feed.placeMealworm(x, y)
	local width = MEALWORM_NATIVE_WIDTH * Constants.PIXEL_SCALE
	local height = MEALWORM_NATIVE_HEIGHT * Constants.PIXEL_SCALE
	local finalX, finalY = computePlacement(width, height, x, y)
	if not finalX then
		return
	end
	local item = createMealwormItem(finalX, finalY)
	table.insert(items, item)
	save()
	return item
end

function Feed.isValidMealwormPosition(x, y)
	local width = MEALWORM_NATIVE_WIDTH * Constants.PIXEL_SCALE
	local height = MEALWORM_NATIVE_HEIGHT * Constants.PIXEL_SCALE
	local finalX = computePlacement(width, height, x, y)
	return finalX ~= nil
end

-- Toolbar descriptors: icon is the toolbar/ghost art and collision
-- footprint; place() decides what actually gets spawned.
Feed.SEED_ITEM = {
	icon = SEED_ICON_PATH,
	width = SEED_ICON_NATIVE_SIZE * Constants.PIXEL_SCALE,
	height = SEED_ICON_NATIVE_SIZE * Constants.PIXEL_SCALE,
	place = Feed.placeSeedPatch,
	isValidPosition = Feed.isValidSeedPatchPosition,
}

Feed.LETTUCE_ITEM = {
	icon = LETTUCE_PATH,
	width = LETTUCE_NATIVE_SIZE * Constants.PIXEL_SCALE,
	height = LETTUCE_NATIVE_SIZE * Constants.PIXEL_SCALE,
	place = Feed.placeLettuce,
	isValidPosition = Feed.isValidLettucePosition,
}

Feed.MEALWORM_ITEM = {
	icon = MEALWORM_PATH,
	width = MEALWORM_NATIVE_WIDTH * Constants.PIXEL_SCALE,
	height = MEALWORM_NATIVE_HEIGHT * Constants.PIXEL_SCALE,
	place = Feed.placeMealworm,
	isValidPosition = Feed.isValidMealwormPosition,
}

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
			})
		else
			table.insert(savedTreats, { x = item.x, y = item.y })
		end
	end
	return { sources = savedSources, treats = savedTreats }
end

-- saved: the "feed" section of src/save.lua's file, a sibling to Coop's
-- "world" section.
function Feed.load(saved)
	saved = saved or {}
	items = {}

	for _, savedSource in ipairs(saved.sources or {}) do
		local item
		if savedSource.type == "lettuce" then
			item = createLettuceItem(savedSource.x, savedSource.y, savedSource.remaining)
		else
			item = createSeedPatch(savedSource.x, savedSource.y, savedSource.remaining, savedSource.offsets)
		end
		table.insert(items, item)
	end

	for _, savedTreat in ipairs(saved.treats or {}) do
		table.insert(items, createMealwormItem(savedTreat.x, savedTreat.y))
	end
end

return Feed
