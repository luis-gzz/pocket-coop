local Constants = require("src.constants")
local Layout = require("src.layout")
local Coop = require("src.coop")
local Wiggle = require("src.wiggle")

-- The bottom UI band's control for placing world objects (CONTEXT.md):
-- reads from ITEMS below instead of hardcoding the hen bed, so a future
-- item is one more definition, not new UI code.
local Toolbar = {}

local ICON_MARGIN = 4 * Constants.PIXEL_SCALE
local ICON_GAP = 4 * Constants.PIXEL_SCALE

-- ms; matches chicken.lua's/coop.lua's own long-press threshold - held here
-- as toolbar.lua's own copy rather than shared, same as their angle/timing.
local LONG_PRESS_TIME = 350
local WIGGLE_ANGLE = 8
local WIGGLE_STEP_TIME = 90

local ITEMS = {
	{
		icon = "assets/objects/eggplace.png",
		width = Coop.BED_WIDTH,
		height = Coop.BED_HEIGHT,
		place = function(x, y)
			Coop.placeBed(x, y)
		end,
		isValidPosition = Coop.isValidBedPosition,
	},
}

function Toolbar.create()
	local band = Layout.getBottomBandRect()
	local centerY = (band.minY + band.maxY) / 2

	local buttonX = band.minX + ICON_MARGIN
	for _, item in ipairs(ITEMS) do
		local icon = display.newImageRect(item.icon, item.width, item.height)
		icon.anchorX = 0
		icon.anchorY = 0.5
		icon.x = buttonX
		icon.y = centerY

		-- Hold-and-drag, mirroring chicken.lua's/coop.lua's long-press shape: a
		-- ghost only appears (and starts wiggling) once the hold clears
		-- LONG_PRESS_TIME, then follows the touch. A release where
		-- item.isValidPosition passes places the item - anywhere else (a
		-- position that wouldn't fit fully in the play area, another band, a
		-- safe-area margin, or a release before the long-press even fires)
		-- cancels with nothing placed.
		local ghost = nil
		local wiggleHandle = nil
		local pendingTouch = false
		local longPressHandle = nil

		local function beginDrag(startX, startY)
			ghost = display.newImageRect(item.icon, item.width, item.height)
			ghost.alpha = 0.7
			ghost.x = startX
			ghost.y = startY
			wiggleHandle = Wiggle.start(ghost, WIGGLE_ANGLE, WIGGLE_STEP_TIME, function()
				return ghost ~= nil
			end)
		end

		local function onTouch(event)
			if event.phase == "began" then
				display.getCurrentStage():setFocus(icon, event.id)
				icon.isFocus = true
				pendingTouch = true
				local startX, startY = event.x, event.y
				longPressHandle = timer.performWithDelay(LONG_PRESS_TIME, function()
					longPressHandle = nil
					if pendingTouch then
						beginDrag(startX, startY)
						pendingTouch = false
					end
				end)
			elseif icon.isFocus then
				if event.phase == "moved" then
					if ghost then
						ghost.x = event.x
						ghost.y = event.y
					end
				elseif event.phase == "ended" or event.phase == "cancelled" then
					display.getCurrentStage():setFocus(icon, nil)
					icon.isFocus = false

					if longPressHandle then
						timer.cancel(longPressHandle)
						longPressHandle = nil
					end
					pendingTouch = false

					if ghost then
						Wiggle.stop(wiggleHandle)
						wiggleHandle = nil
						if event.phase == "ended" and item.isValidPosition(event.x, event.y) then
							item.place(event.x, event.y)
						end
						ghost:removeSelf()
						ghost = nil
					end
				end
			end
			return true
		end
		icon:addEventListener("touch", onTouch)

		buttonX = buttonX + item.width + ICON_GAP
	end
end

return Toolbar
