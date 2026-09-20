local Constants = require("src.util.constants")
local YSort = require("src.systems.y_sort")
local Wiggle = require("src.util.wiggle")
local Island = require("src.systems.island")

-- The view + drag side of a hen bed (CONTEXT.md). Garden owns the placed
-- beds themselves (the { x, y, egg } records) and their placement rules;
-- this owns the display object and repositioning.
local Bed = {}

local IMAGE_PATH = "assets/objects/bed1.png"
local NATIVE_WIDTH, NATIVE_HEIGHT = 23, 15

Bed.WIDTH = NATIVE_WIDTH * Constants.PIXEL_SCALE
Bed.HEIGHT = NATIVE_HEIGHT * Constants.PIXEL_SCALE
Bed.DESCRIPTOR = { icon = IMAGE_PATH, width = Bed.WIDTH, height = Bed.HEIGHT, type = "bed" }

-- ms; matches chicken.lua's own long-press threshold. Duplicated rather than
-- shared - bed dragging (free movement, validate-only-on-drop, snap back)
-- differs enough from the chicken's (continuously clamped, FSM-integrated)
-- that a shared module would only be this timer/focus bookkeeping.
local LONG_PRESS_TIME = 350
local WIGGLE_ANGLE = 8
local WIGGLE_STEP_TIME = 90

-- Whether a bed centered at (x, y) would sit fully inside the play area -
-- every edge, not just its center point. Only needs Island's static bounds,
-- not any other bed's position, so this stays self-contained rather than
-- reaching into Garden - unlike food items, which do need to check overlap
-- against other placed items (see mealworm.lua's resolveDrop).
function Bed.isValidPosition(x, y)
	local bounds = Island.getInnerBounds()
	return x - Bed.WIDTH / 2 >= bounds.minX
		and x + Bed.WIDTH / 2 <= bounds.maxX
		and y - Bed.HEIGHT / 2 >= bounds.minY
		and y + Bed.HEIGHT / 2 <= bounds.maxY
end

-- record: the { x, y, egg } table Garden owns, so this can mutate record.x/y
-- directly on a successful drag and Garden's own bed list stays in sync.
-- onMoved() is called right after that mutation, so Garden can save.
--
-- A bed is a group so an occupying egg can be inserted on top of the nest
-- art and stay visually "inside" it (see egg.lua), instead of competing with
-- the nest for Y-sort depth. The group itself is deliberately NOT registered
-- with YSort: a bed is a flat, wide floor object, and a chicken or egg
-- standing anywhere on it should always read as in front of it - leaving it
-- out of the depth-sort registry means every registered world object gets
-- toFront()'d above it every frame, so it always renders furthest back.
function Bed.new(record, onMoved)
	local group = display.newGroup()
	YSort.getGroup():insert(group)
	group.x = record.x
	group.y = record.y

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
					if event.phase == "ended" and Bed.isValidPosition(group.x, group.y) then
						record.x, record.y = group.x, group.y
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
