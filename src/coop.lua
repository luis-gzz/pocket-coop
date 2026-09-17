local Constants = require("src.constants")
local YSort = require("src.y_sort")
local Island = require("src.island")
local Wiggle = require("src.wiggle")

-- The shared owner of every placed hen bed and active egg, plus the
-- player's collected-egg count (CONTEXT.md). A hen's Gauges (its lay clock)
-- decides WHEN she lays; this module decides WHERE the resulting egg goes,
-- since beds and eggs belong to the coop as a whole, not to any one hen
-- (ADR-0007).
local Coop = {}

local BED_IMAGE_PATH = "assets/objects/bed1.png"
local BED_NATIVE_WIDTH, BED_NATIVE_HEIGHT = 23, 15
local BED_WIDTH = BED_NATIVE_WIDTH * Constants.PIXEL_SCALE
local BED_HEIGHT = BED_NATIVE_HEIGHT * Constants.PIXEL_SCALE

local EGG_IMAGE_PATH = "assets/fauna/ChickenEgg.png"
local EGG_NATIVE_WIDTH, EGG_NATIVE_HEIGHT = 7, 8
local EGG_WIDTH = EGG_NATIVE_WIDTH * Constants.PIXEL_SCALE
local EGG_HEIGHT = EGG_NATIVE_HEIGHT * Constants.PIXEL_SCALE

-- World points; scatters a floor egg around the bed it overflowed from, the
-- same idea as src/gauges.lua's dropping jitter.
local FLOOR_EGG_JITTER_RADIUS = 12

-- ms; matches src/chicken.lua's own long-press threshold. Duplicated rather
-- than shared - bed dragging (free movement, validate-only-on-drop, snap
-- back) differs enough from the chicken's (continuously clamped, FSM-
-- integrated) that a shared module would only be this timer/focus
-- bookkeeping.
local LONG_PRESS_TIME = 350

-- Wiggle while held, matching src/chicken.lua's own wiggle-while-held values
-- - a shared "this is being picked up" visual language across world objects.
local WIGGLE_ANGLE = 8
local WIGGLE_STEP_TIME = 90

local beds = {} -- { view, x, y, egg }
local eggs = {} -- { view, bed (nil for a floor egg), x, y }
local collectedCount = 0
local onSave = nil

local function save()
	if onSave then
		onSave()
	end
end

function Coop.setSaveCallback(fn)
	onSave = fn
end

function Coop.getCollectedCount()
	return collectedCount
end

-- Folds into the cleanliness target the same way droppings do (ADR-0004) -
-- only floor eggs are dirty; eggs sitting in a bed are tidy.
function Coop.getFloorEggCount()
	local count = 0
	for _, egg in ipairs(eggs) do
		if not egg.bed then
			count = count + 1
		end
	end
	return count
end

local function distanceSquared(ax, ay, bx, by)
	local dx, dy = ax - bx, ay - by
	return dx * dx + dy * dy
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

local function jitteredPosition(x, y)
	local angle = math.random() * math.pi * 2
	local radius = math.random() * FLOOR_EGG_JITTER_RADIUS
	return x + math.cos(angle) * radius, y + math.sin(angle) * radius
end

-- Whether a bed centered at (x, y) would sit fully inside the play area -
-- every edge, not just its center point. Shared by the toolbar's initial
-- placement and dragging an already-placed bed, so both use one rule.
local function isValidBedPosition(x, y)
	local bounds = Island.getInnerBounds()
	return x - BED_WIDTH / 2 >= bounds.minX
		and x + BED_WIDTH / 2 <= bounds.maxX
		and y - BED_HEIGHT / 2 >= bounds.minY
		and y + BED_HEIGHT / 2 <= bounds.maxY
end
Coop.isValidBedPosition = isValidBedPosition

-- Hold-and-drag a placed bed, mirroring src/chicken.lua's own long-press-
-- then-drag shape (timer + pendingTouch + setFocus) but with different
-- semantics: free movement while dragging (no continuous clamp), validated
-- only on release - a drop that wouldn't fit fully in the play area snaps
-- the bed back to where it was instead of committing.
local function attachBedDrag(bed, group, nest)
	local pendingTouch = false
	local isDragging = false
	local longPressHandle = nil
	local originalX, originalY
	local dragOffsetX, dragOffsetY
	local wiggleHandle = nil

	local function beginDrag(startX, startY)
		isDragging = true
		originalX, originalY = bed.x, bed.y
		dragOffsetX = group.x - startX
		dragOffsetY = group.y - startY
		wiggleHandle = Wiggle.start(group, WIGGLE_ANGLE, WIGGLE_STEP_TIME, function()
			return isDragging
		end)
	end

	local function onTouch(event)
		if event.phase == "began" then
			display.getCurrentStage():setFocus(nest, event.id)
			nest.isFocus = true
			pendingTouch = true
			local startX, startY = event.x, event.y
			longPressHandle = timer.performWithDelay(LONG_PRESS_TIME, function()
				longPressHandle = nil
				if pendingTouch then
					beginDrag(startX, startY)
					pendingTouch = false
				end
			end)
		elseif nest.isFocus then
			if event.phase == "moved" then
				if isDragging then
					group.x = event.x + dragOffsetX
					group.y = event.y + dragOffsetY
				end
			elseif event.phase == "ended" or event.phase == "cancelled" then
				display.getCurrentStage():setFocus(nest, nil)
				nest.isFocus = false

				if longPressHandle then
					timer.cancel(longPressHandle)
					longPressHandle = nil
				end
				pendingTouch = false

				if isDragging then
					isDragging = false
					Wiggle.stop(wiggleHandle)
					wiggleHandle = nil
					if event.phase == "ended" and isValidBedPosition(group.x, group.y) then
						bed.x, bed.y = group.x, group.y
						save()
					else
						transition.to(group, { x = originalX, y = originalY, time = 150 })
					end
				end
			end
		end
		return true
	end
	nest:addEventListener("touch", onTouch)
end

-- A bed is a group so an occupying egg can be inserted on top of the nest
-- art and stay visually "inside" it, instead of competing with the nest for
-- Y-sort depth at the same position (which would let the nest render over
-- the egg half the time).
--
-- The group itself is deliberately NOT registered with YSort: a bed is a
-- flat, wide floor object, and a chicken or egg standing anywhere on it
-- should always read as in front of it, not just when it's lower on screen.
-- Leaving it out of the depth-sort registry means every registered world
-- object (chicken, droppings, floor eggs) gets toFront()'d above it every
-- frame, so it always renders furthest back among world objects - while
-- still sitting inside the world group, above the island beneath it.
--
-- bed: the { x, y, egg } table (view not yet set) built by the caller, so
-- the drag handler above can close over and mutate the same entry that
-- `beds`, findNearestBed, and Coop.getSaveData all read.
local function createBedView(bed)
	local group = display.newGroup()
	YSort.getGroup():insert(group)
	group.x = bed.x
	group.y = bed.y

	local nest = display.newImageRect(group, BED_IMAGE_PATH, BED_WIDTH, BED_HEIGHT)
	nest.x = 0
	nest.y = 0

	attachBedDrag(bed, group, nest)

	return group
end

local function createFloorEggView(x, y)
	local image = display.newImageRect(EGG_IMAGE_PATH, EGG_WIDTH, EGG_HEIGHT)
	YSort.getGroup():insert(image)
	image.x = x
	image.y = y
	YSort.add(image, function(view)
		return view.y + EGG_HEIGHT / 2
	end)
	return image
end

local function onEggTap(egg)
	return function()
		Coop.collectEgg(egg)
		return true
	end
end

local function attachEggToBed(bed)
	local eggImage = display.newImageRect(bed.view, EGG_IMAGE_PATH, EGG_WIDTH, EGG_HEIGHT)
	eggImage.x = 0
	-- eggImage is center-anchored, so shifting it up by half its own height
	-- puts its bottom edge - not its center - at the bed's center point,
	-- reading as sitting in the nest rather than floating above it.
	eggImage.y = -EGG_HEIGHT / 2
	local egg = { bed = bed, view = eggImage }
	eggImage:addEventListener("tap", onEggTap(egg))
	bed.egg = egg
	table.insert(eggs, egg)
	return egg
end

local function createFloorEgg(x, y)
	local image = createFloorEggView(x, y)
	local egg = { view = image, bed = nil, x = x, y = y }
	image:addEventListener("tap", onEggTap(egg))
	table.insert(eggs, egg)
	return egg
end

function Coop.placeBed(x, y)
	local bed = { x = x, y = y, egg = nil }
	bed.view = createBedView(bed)
	table.insert(beds, bed)
	save()
	return bed
end

-- The toolbar's descriptor for this item (CONTEXT.md's "Toolbar"): icon,
-- footprint, and its place/isValidPosition callbacks bundled together so
-- toolbar.lua never needs to know a bed's own image path or dimensions.
Coop.BED_ITEM = {
	icon = BED_IMAGE_PATH,
	width = BED_WIDTH,
	height = BED_HEIGHT,
	place = Coop.placeBed,
	isValidPosition = Coop.isValidBedPosition,
}

-- Called by a hen's Gauges when its lay clock fires (ADR-0007). x, y is the
-- hen's position at the moment of laying. Placement priority: nearest open
-- bed, else near the closest bed (all occupied), else a random spot in the
-- play area (no beds at all).
function Coop.hatchEgg(x, y)
	local openBed = findNearestBed(x, y, true)
	if openBed then
		attachEggToBed(openBed)
		save()
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
	save()
end

-- Removes an egg (in a bed or on the floor), frees its bed if it had one,
-- and credits the player's stash. Shared by a direct tap and any future
-- collect-all affordance.
function Coop.collectEgg(egg)
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
	save()
end

function Coop.getSaveData()
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

	return {
		collectedCount = collectedCount,
		beds = savedBeds,
		eggs = savedEggs,
	}
end

-- saved: an optional table (the "world" section of src/save.lua's file, a
-- sibling to the chicken's own data) to resume from.
function Coop.load(saved)
	saved = saved or {}
	collectedCount = saved.collectedCount or 0
	beds = {}
	eggs = {}

	for _, savedBed in ipairs(saved.beds or {}) do
		local bed = { x = savedBed.x, y = savedBed.y, egg = nil }
		bed.view = createBedView(bed)
		table.insert(beds, bed)
	end

	for _, savedEgg in ipairs(saved.eggs or {}) do
		local bed = savedEgg.bedIndex and beds[savedEgg.bedIndex]
		if bed then
			attachEggToBed(bed)
		else
			createFloorEgg(savedEgg.x, savedEgg.y)
		end
	end
end

return Coop
