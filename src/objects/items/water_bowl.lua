local Constants = require("src.util.constants")
local YSort = require("src.systems.y_sort")
local Shadow = require("src.objects.shadow")
local Wiggle = require("src.util.wiggle")
local Tooltip = require("src.ui.tooltip")
local Footprints = require("src.systems.footprints")

-- The view + drag side of a water bowl (CONTEXT.md). Bowls owns the record
-- and placement rules; this owns the display object and repositioning.
local WaterBowl = {}

local FULL_PATH = "assets/objects/water_bowl_full.png"
local MID_PATH = "assets/objects/water_bowl_mid.png"
local EMPTY_PATH = "assets/objects/water_bowl_empty.png"
-- At or below this share of its water, a bowl shows the half-full sprite.
local MID_SHARE = 0.5
local NATIVE_WIDTH, NATIVE_HEIGHT = 21, 13

WaterBowl.WIDTH = NATIVE_WIDTH * Constants.PIXEL_SCALE
WaterBowl.HEIGHT = NATIVE_HEIGHT * Constants.PIXEL_SCALE
WaterBowl.DESCRIPTOR = { icon = FULL_PATH, width = WaterBowl.WIDTH, height = WaterBowl.HEIGHT, type = "water_bowl" }

-- Share of its height above the footprint (CONTEXT.md's Footprint).
WaterBowl.FOOTPRINT_SHARE = 0.25

-- How far in from the bowl's side a peck point lands, and the rows the
-- water spans (native px from the top), so the beak reaches the water.
-- The inset keeps a drinking chicken's front foot just off the rim.
local PECK_INSET = 2.5
local WATER_TOP, WATER_BOTTOM = 4, 7

-- ms; matches chicken.lua's own long-press threshold.
local LONG_PRESS_TIME = 350
local WIGGLE_ANGLE = 8
local WIGGLE_STEP_TIME = 90

-- record: the bowl Bowls owns; a drag mutates record.x/y, then onMoved()
-- saves. resolvePlacement(x, y) returns the final x, y or nil to snap back.
-- Sorts by its sort line (ADR-0021), like a hen bed.
function WaterBowl.new(record, onMoved, resolvePlacement)
	local group = display.newGroup()
	YSort.getGroup():insert(group)
	group.x = record.x
	group.y = record.y
	YSort.add(group, function(view)
		return Footprints.sortLine({ x = view.x, y = view.y, width = WaterBowl.WIDTH, height = WaterBowl.HEIGHT,
			footprintShare = WaterBowl.FOOTPRINT_SHARE })
	end)

	Shadow.new(group, NATIVE_WIDTH).y = WaterBowl.HEIGHT / 2
	local full = display.newImageRect(group, FULL_PATH, WaterBowl.WIDTH, WaterBowl.HEIGHT)
	local mid = display.newImageRect(group, MID_PATH, WaterBowl.WIDTH, WaterBowl.HEIGHT)
	local empty = display.newImageRect(group, EMPTY_PATH, WaterBowl.WIDTH, WaterBowl.HEIGHT)

	function record.updateVisual()
		local share = record.water / record.capacity
		full.isVisible = share > MID_SHARE
		mid.isVisible = share > 0 and share <= MID_SHARE
		empty.isVisible = share <= 0
	end
	record.updateVisual()

	-- Near the side facing the chicken, anywhere in the water's rows; the
	-- chicken stands lower, so she's below the sort line and draws in front.
	function record.pickPeckPoint(facing)
		local inset = PECK_INSET * Constants.PIXEL_SCALE
		local top = record.y - WaterBowl.HEIGHT / 2
		local row = WATER_TOP + math.random() * (WATER_BOTTOM - WATER_TOP)
		return {
			x = record.x - facing * (WaterBowl.WIDTH / 2 - inset),
			y = top + row * Constants.PIXEL_SCALE,
		}
	end

	-- A transparent hit target over the whole bowl, whichever sprite shows.
	local hitArea = display.newRect(group, 0, 0, WaterBowl.WIDTH, WaterBowl.HEIGHT)
	hitArea:setFillColor(0, 0, 0, 0.01)

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

	local function showTooltip()
		Tooltip.show({
			source = record,
			x = record.x,
			y = record.y,
			rows = {
				{ label = "Water", getValue = function() return record.water / record.capacity * 100 end },
			},
		})
	end

	local function onTouch(event)
		if event.phase == "began" then
			display.getCurrentStage():setFocus(hitArea, event.id)
			hitArea.isFocus = true
			pendingTouch = true
			local startX, startY = event.x, event.y
			longPressHandle = timer.performWithDelay(LONG_PRESS_TIME, function()
				longPressHandle = nil
				if pendingTouch then
					beginDrag(startX, startY)
					pendingTouch = false
				end
			end)
		elseif hitArea.isFocus then
			if event.phase == "moved" then
				if isDragging then
					group.x = event.x + dragOffsetX
					group.y = event.y + dragOffsetY
				end
			elseif event.phase == "ended" or event.phase == "cancelled" then
				display.getCurrentStage():setFocus(hitArea, nil)
				hitArea.isFocus = false

				-- Released before the long press fired: a tap, so open the tooltip.
				if longPressHandle then
					timer.cancel(longPressHandle)
					longPressHandle = nil
					if pendingTouch and event.phase == "ended" then
						showTooltip()
					end
				end
				pendingTouch = false

				if isDragging then
					isDragging = false
					Wiggle.stop(wiggleHandle)
					wiggleHandle = nil
					-- Releasing in place synthesizes a tap; don't let it close a tooltip.
					Tooltip.ignoreNextTap()
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
	hitArea:addEventListener("touch", onTouch)

	-- Solar2D hit-tests "tap" separately from "touch" - this blocks a tap
	-- falling through to what's underneath.
	hitArea:addEventListener("tap", function()
		return true
	end)

	return group
end

return WaterBowl
