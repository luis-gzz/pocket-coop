local Constants = require("src.util.constants")
local YSort = require("src.systems.y_sort")
local Wiggle = require("src.util.wiggle")
local Island = require("src.systems.island")

-- The view + drag side of a hen bed (CONTEXT.md). Garden owns the placed
-- beds themselves (the { x, y, eggs } records) and their placement rules;
-- this owns the display object and repositioning.
local Bed = {}

local IMAGE_PATH = "assets/objects/bed1.png"
local NATIVE_WIDTH, NATIVE_HEIGHT = 23, 15

Bed.WIDTH = NATIVE_WIDTH * Constants.PIXEL_SCALE
Bed.HEIGHT = NATIVE_HEIGHT * Constants.PIXEL_SCALE
Bed.DESCRIPTOR = { icon = IMAGE_PATH, width = Bed.WIDTH, height = Bed.HEIGHT, type = "bed" }

-- A bed holds up to this many eggs at once (CONTEXT.md's Egg slot).
Bed.SLOT_COUNT = 3

-- x offsets (native px) for each egg slot, in fill order: Garden.findOpenSlot
-- walks slots 1..SLOT_COUNT in this order, so the middle egg lands first,
-- then left, then right. Clustered closer than the bed's full width so the
-- three read as a little pile rather than spread edge to edge. y is left to
-- Egg.newInBed's own anchor.
local SLOT_OFFSETS_NATIVE = { 0, -5, 5 }

-- The local x offset (already scaled) for one of a bed's fixed egg slots -
-- Garden positions each egg it attaches to a bed using this.
function Bed.getSlotOffsetX(index)
	return SLOT_OFFSETS_NATIVE[index] * Constants.PIXEL_SCALE
end

-- ms; matches chicken.lua's own long-press threshold. Duplicated rather than
-- shared - bed dragging (free movement, validate-only-on-drop, snap back)
-- differs enough from the chicken's (continuously clamped, FSM-integrated)
-- that a shared module would only be this timer/focus bookkeeping.
local LONG_PRESS_TIME = 350
local WIGGLE_ANGLE = 8
local WIGGLE_STEP_TIME = 90

-- Whether a bed centered at (x, y) would sit fully inside the play area -
-- every edge, not just its center point. Only checks Island's static
-- bounds; overlap against other beds is Garden's own resolveBedPlacement
-- (ADR-0014), the same split Feed's computePlacement already uses for food
-- items (see mealworm.lua's resolveDrop).
function Bed.isValidPosition(x, y)
	local bounds = Island.getInnerBounds()
	return x - Bed.WIDTH / 2 >= bounds.minX
		and x + Bed.WIDTH / 2 <= bounds.maxX
		and y - Bed.HEIGHT / 2 >= bounds.minY
		and y + Bed.HEIGHT / 2 <= bounds.maxY
end

-- record: the { x, y, eggs } table Garden owns, so this can mutate record.x/y
-- directly on a successful drag and Garden's own bed list stays in sync.
-- onMoved() is called right after that mutation, so Garden can save.
-- resolvePlacement(x, y) is Garden's own bed-vs-bed overlap check
-- (Garden.resolveBedPlacement, ADR-0014) - it returns the final (possibly
-- nudged) x, y on a valid drop, or nil to snap back.
--
-- A bed is a group so an occupying egg can be inserted on top of the nest
-- art and stay visually "inside" it (see egg.lua), instead of competing with
-- the nest for Y-sort depth. The group is registered with the floor layer
-- (ADR-0014), not the main YSort group: it sorts against other beds by the
-- same bottom-edge rule (ADR-0006), but the floor layer as a whole always
-- renders behind every object in the main sort, so a chicken or egg standing
-- anywhere on a bed still reads as in front of it.
function Bed.new(record, onMoved, resolvePlacement)
	local group = display.newGroup()
	YSort.getFloorGroup():insert(group)
	group.x = record.x
	group.y = record.y
	YSort.addToFloor(group, function(view)
		return view.y + Bed.HEIGHT / 2
	end)

	local nest = display.newImageRect(group, IMAGE_PATH, Bed.WIDTH, Bed.HEIGHT)
	nest.x = 0
	nest.y = 0

	local pendingTouch = false
	local isDragging = false
	local longPressHandle = nil
	local originalX, originalY
	local dragOffsetX, dragOffsetY
	local wiggleHandle = nil

	local function beginDrag(startX, startY)
		isDragging = true
		originalX, originalY = record.x, record.y
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
					local finalX, finalY
					if event.phase == "ended" then
						finalX, finalY = resolvePlacement(group.x, group.y)
					end
					if finalX then
						group.x, group.y = finalX, finalY
						record.x, record.y = finalX, finalY
						onMoved()
					else
						transition.to(group, { x = originalX, y = originalY, time = 150 })
					end
				end
			end
		end
		return true
	end
	nest:addEventListener("touch", onTouch)

	return group
end

return Bed
