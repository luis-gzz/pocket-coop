local Constants = require("src.util.constants")
local YSort = require("src.systems.y_sort")
local Shadow = require("src.objects.shadow")
local Wiggle = require("src.util.wiggle")
local Footprints = require("src.systems.footprints")

-- The view + drag side of a hen bed (CONTEXT.md). Garden owns the placed
-- beds themselves (the { x, y, eggs } records) and their placement rules;
-- this owns the display object and repositioning.
local Bed = {}

-- A planked nesting crate. Natural, red, and blue variants sit beside it
-- (bed_crate_*.png); walnut is the default for now.
local IMAGE_PATH = "assets/objects/bed_crate_walnut.png"
local NATIVE_WIDTH, NATIVE_HEIGHT = 27, 18

Bed.WIDTH = NATIVE_WIDTH * Constants.PIXEL_SCALE
Bed.HEIGHT = NATIVE_HEIGHT * Constants.PIXEL_SCALE
Bed.DESCRIPTOR = { icon = IMAGE_PATH, width = Bed.WIDTH, height = Bed.HEIGHT, type = "bed" }

-- Share of its height above the footprint (CONTEXT.md's Footprint).
Bed.FOOTPRINT_SHARE = 0.25

-- A bed holds up to this many eggs at once (CONTEXT.md's Egg slot).
Bed.SLOT_COUNT = 3

-- x offsets (native px) for each egg slot, in fill order: Garden.findOpenSlot
-- walks slots 1..SLOT_COUNT in this order, so the middle egg lands first,
-- then left, then right. Clustered closer than the bed's full width so the
-- three read as a little pile rather than spread edge to edge. y is left to
-- Egg.newInBed's own anchor.
local SLOT_OFFSETS_NATIVE = { 0, -6, 6 }

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

-- record: the { x, y, eggs } table Garden owns, so this can mutate record.x/y
-- directly on a successful drag and Garden's own bed list stays in sync.
-- onMoved() is called right after that mutation, so Garden can save.
-- resolvePlacement(x, y) is Garden's own fixture spacing check
-- (Garden.resolveBedPlacement, ADR-0014) - it returns the final (possibly
-- nudged) x, y on a valid drop, or nil to snap back.
--
-- A bed is a group so an occupying egg can be inserted on top of the nest
-- art and stay visually "inside" it (see egg.lua), instead of competing with
-- the nest for Y-sort depth. The group sorts in the main sort by its sort
-- line (ADR-0021), so a chicken passing behind is partly hidden.
function Bed.new(record, onMoved, resolvePlacement)
	local group = display.newGroup()
	YSort.getGroup():insert(group)
	group.x = record.x
	group.y = record.y
	YSort.add(group, function(view)
		return Footprints.sortLine({ x = view.x, y = view.y, width = Bed.WIDTH, height = Bed.HEIGHT,
			footprintShare = Bed.FOOTPRINT_SHARE })
	end)

	Shadow.new(group, NATIVE_WIDTH).y = Bed.HEIGHT / 2
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
		record.dragging = true
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
						record.dragging = false
						onMoved()
					else
						transition.to(group, {
							x = originalX,
							y = originalY,
							time = 150,
							onComplete = function()
								record.dragging = false
							end,
						})
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
