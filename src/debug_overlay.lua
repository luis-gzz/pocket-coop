local TimeScale = require("src.time_scale")
local Constants = require("src.constants")

-- A small corner button that opens a popover of discrete time-scale
-- presets, for tuning. Owns no game logic - purely pokes TimeScale.
local DebugOverlay = {}

-- All spatial constants below are native * Constants.PIXEL_SCALE, like every
-- other piece of art/UI in the project, so this overlay scales along with
-- the rest of the game if PIXEL_SCALE ever changes.
local SCREEN_MARGIN = 4 * Constants.PIXEL_SCALE
local TOGGLE_WIDTH = 35 * Constants.PIXEL_SCALE
local TOGGLE_HEIGHT = 14 * Constants.PIXEL_SCALE
local BUTTON_WIDTH = 25 * Constants.PIXEL_SCALE
local BUTTON_HEIGHT = 14 * Constants.PIXEL_SCALE
local BUTTON_GAP = 3 * Constants.PIXEL_SCALE
local POPOVER_GAP = 3 * Constants.PIXEL_SCALE
local CORNER_RADIUS = 2 * Constants.PIXEL_SCALE
local STROKE_WIDTH = 0.5 * Constants.PIXEL_SCALE

function DebugOverlay.create()
	local root = display.newGroup()
	local x = display.screenOriginX + SCREEN_MARGIN
	local y = display.screenOriginY + SCREEN_MARGIN

	local toggle = display.newRoundedRect(root, x, y, TOGGLE_WIDTH, TOGGLE_HEIGHT, CORNER_RADIUS)
	toggle.anchorX = 0
	toggle.anchorY = 0
	toggle:setFillColor(0.92, 0.92, 0.92)
	toggle.strokeWidth = STROKE_WIDTH
	toggle:setStrokeColor(0.4, 0.4, 0.4)

	local toggleLabel = display.newText(root, "", x + TOGGLE_WIDTH / 2, y + TOGGLE_HEIGHT / 2, Constants.FONT, Constants.FONT_SIZE_SMALL)
	toggleLabel:setFillColor(0, 0, 0)

	local function refreshLabel()
		toggleLabel.text = "Debug " .. TimeScale.get() .. "x"
	end
	refreshLabel()

	local current = nil -- { dismiss, group }

	local function hidePopover()
		if not current then
			return
		end
		current.dismiss:removeSelf()
		current.group:removeSelf()
		current = nil
	end

	local function showPopover()
		hidePopover()

		-- Same full-screen-dismiss-rect-with-a-frame-deferred-listener pattern
		-- as src/tooltip.lua, so the tap that opens this popover doesn't also
		-- generate a synthesized "tap" that instantly closes it.
		local dismiss = display.newRect(
			display.screenOriginX + display.actualContentWidth / 2,
			display.screenOriginY + display.actualContentHeight / 2,
			display.actualContentWidth,
			display.actualContentHeight
		)
		dismiss:setFillColor(0, 0, 0, 0.01)
		timer.performWithDelay(1, function()
			pcall(function()
				dismiss:addEventListener("tap", function()
					hidePopover()
					return true
				end)
			end)
		end)

		local group = display.newGroup()
		group.x = x
		group.y = y + TOGGLE_HEIGHT + POPOVER_GAP

		local buttonX = 0
		for _, preset in ipairs(TimeScale.PRESETS) do
			local button = display.newRoundedRect(group, buttonX, 0, BUTTON_WIDTH, BUTTON_HEIGHT, CORNER_RADIUS)
			button.anchorX = 0
			button.anchorY = 0
			button:setFillColor(0.92, 0.92, 0.92)
			button.strokeWidth = STROKE_WIDTH
			button:setStrokeColor(0.4, 0.4, 0.4)

			local label = display.newText(group, preset .. "x", buttonX + BUTTON_WIDTH / 2, BUTTON_HEIGHT / 2, Constants.FONT, Constants.FONT_SIZE_SMALL)
			label:setFillColor(0, 0, 0)

			button:addEventListener("tap", function()
				TimeScale.set(preset)
				refreshLabel()
				return true
			end)

			buttonX = buttonX + BUTTON_WIDTH + BUTTON_GAP
		end

		current = { dismiss = dismiss, group = group }
	end

	toggle:addEventListener("tap", function()
		if current then
			hidePopover()
		else
			showPopover()
		end
		return true
	end)

	return root
end

return DebugOverlay
