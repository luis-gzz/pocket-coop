local Constants = require("src.util.constants")
local Color = require("src.util.color")

-- Welcome-back card shown after a full offline catch-up. Dismissed by OK or
-- any outside tap, which never reaches the world; the game keeps running.
local WelcomeCard = {}

-- All spatial constants are native * Constants.PIXEL_SCALE, like every other
-- piece of UI in the project.
local PANEL_WIDTH = 110 * Constants.PIXEL_SCALE
local PANEL_PADDING = 8 * Constants.PIXEL_SCALE
local PANEL_CORNER_RADIUS = 3 * Constants.PIXEL_SCALE
local PANEL_STROKE_WIDTH = 1 * Constants.PIXEL_SCALE
local TEXT_BUTTON_GAP = 6 * Constants.PIXEL_SCALE
local BUTTON_WIDTH = 30 * Constants.PIXEL_SCALE
local BUTTON_HEIGHT = 14 * Constants.PIXEL_SCALE
local BUTTON_CORNER_RADIUS = 2 * Constants.PIXEL_SCALE

-- Shared with src/ui/tooltip.lua's panel.
local PANEL_FILL_HEX = "f2f0e5"
local PANEL_STROKE_HEX = "3a3858"
local BUTTON_FILL_HEX = "8ab060"

local current = nil -- { dismiss, group }

-- "N min" under an hour, "N hrs" otherwise, rounded down ("1 hr"
-- singular). Real time away - not the capped time catch-up computed with.
function WelcomeCard.formatAway(seconds)
	local minutes = math.floor(seconds / 60)
	if minutes < 60 then
		return minutes .. " min"
	end
	local hours = math.floor(minutes / 60)
	return hours .. (hours == 1 and " hr" or " hrs")
end

function WelcomeCard.hide()
	if not current then
		return
	end
	current.dismiss:removeSelf()
	current.group:removeSelf()
	current = nil
end

function WelcomeCard.show(elapsedSeconds)
	WelcomeCard.hide()

	local centerX = display.screenOriginX + display.actualContentWidth / 2
	local centerY = display.screenOriginY + display.actualContentHeight / 2

	-- Full-screen tap catcher. Listener attached a frame late (as in tooltip.lua)
	-- so the tap that opened the card doesn't close it.
	local dismiss = display.newRect(centerX, centerY, display.actualContentWidth, display.actualContentHeight)
	dismiss:setFillColor(0, 0, 0, 0.01)
	dismiss:addEventListener("touch", function()
		return true
	end)
	timer.performWithDelay(1, function()
		pcall(function()
			dismiss:addEventListener("tap", function()
				WelcomeCard.hide()
				return true
			end)
		end)
	end)

	local group = display.newGroup()
	group.x, group.y = centerX, centerY

	local textWidth = PANEL_WIDTH - PANEL_PADDING * 2
	local text = display.newText({
		text = "Welcome back! You've been away for " .. WelcomeCard.formatAway(elapsedSeconds) .. ".",
		width = textWidth,
		font = Constants.FONT,
		fontSize = Constants.FONT_SIZE_SMALL,
		align = "center",
	})
	text:setFillColor(0.2, 0.2, 0.2)

	local panelHeight = PANEL_PADDING * 2 + text.height + TEXT_BUTTON_GAP + BUTTON_HEIGHT
	local panel = display.newRoundedRect(group, 0, 0, PANEL_WIDTH, panelHeight, PANEL_CORNER_RADIUS)
	panel:setFillColor(Color.hexToRGB(PANEL_FILL_HEX))
	panel.strokeWidth = PANEL_STROKE_WIDTH
	panel:setStrokeColor(Color.hexToRGB(PANEL_STROKE_HEX))
	-- Taps on the panel itself (outside the button) do nothing, rather than
	-- falling through to the dismiss rect.
	panel:addEventListener("tap", function()
		return true
	end)

	group:insert(text)
	text.anchorY = 0
	text.y = -panelHeight / 2 + PANEL_PADDING

	local buttonY = panelHeight / 2 - PANEL_PADDING - BUTTON_HEIGHT / 2
	local button = display.newRoundedRect(group, 0, buttonY, BUTTON_WIDTH, BUTTON_HEIGHT, BUTTON_CORNER_RADIUS)
	button:setFillColor(Color.hexToRGB(BUTTON_FILL_HEX))
	button.strokeWidth = PANEL_STROKE_WIDTH
	button:setStrokeColor(Color.hexToRGB(PANEL_STROKE_HEX))
	button:addEventListener("tap", function()
		WelcomeCard.hide()
		return true
	end)

	local label = display.newText(group, "OK", 0, buttonY, Constants.FONT, Constants.FONT_SIZE_SMALL)
	label:setFillColor(0.2, 0.2, 0.2)

	current = { dismiss = dismiss, group = group }
end

return WelcomeCard
