local Constants = require("src.util.constants")
local Layout = require("src.ui.layout")
local Font = require("src.ui.font")
local Garden = require("src.systems.garden")
local Slot = require("src.ui.slot")
local Frame = require("src.ui.frame")
local BarnView = require("src.ui.barn_view")
local DropZone = require("src.ui.drop_zone")

-- The top UI band's at-a-glance stat displays - the egg counter (the
-- player's total collected eggs, their stash, not the number of eggs
-- currently sitting uncollected in the world - see CONTEXT.md), framed,
-- and the barn button at its right, which opens the barn view.
local Hud = {}

-- All in HUD art px (Layout.getHudRect's pixel), world-sized where it fits (ADR-0025).
local ICON_NATIVE_WIDTH, ICON_NATIVE_HEIGHT = 6, 7
local ICON_TEXT_GAP = 3
local BUTTON_GAP = 3
local FRAME_PADDING = 3 -- inside the egg counter's frame, each end
local BARN_ICON_PIXELS = 9
local FONT_PIXELS = 11

local ICON_PATH = "assets/fauna/ChickenEgg.png"
local BARN_ICON_PATH = "assets/objects/barn_icon_small.png"

function Hud.create()
	local buttonRect = Layout.getHudRect()
	local pixel = buttonRect.pixel
	local centerY = (buttonRect.minY + buttonRect.maxY) / 2
	local barnButton = Slot.new(display.getCurrentStage(), buttonRect.minX, buttonRect.minY, nil, buttonRect.size, pixel)
	Slot.drawPixelIcon(barnButton, BARN_ICON_PATH, BARN_ICON_PIXELS,
		(Layout.HUD_PIXELS - BARN_ICON_PIXELS) / 2, pixel)
	barnButton.background:addEventListener("tap", function()
		BarnView.show()
		return true
	end)
	DropZone.onLanded(function(area)
		if area == "barn" then
			barnButton.flash()
		end
	end)

	-- The egg counter's frame, as tall as the barn button, widening with the count.
	local counter = display.newGroup()
	local frame = nil
	local frameRight = buttonRect.minX - BUTTON_GAP * pixel
	local iconWidth = ICON_NATIVE_WIDTH * pixel
	local fontSize = FONT_PIXELS * pixel

	local icon = display.newImageRect(counter, ICON_PATH, iconWidth, ICON_NATIVE_HEIGHT * pixel)
	icon.anchorX = 0
	-- The egg art has no transparent padding, so its center is its visual center.
	icon.anchorY = 0.5
	icon.y = centerY

	-- No explicit width/height here: constraining newText's box height to
	-- icon.height (much shorter than FONT_SIZE_SMALL's actual line height)
	-- clipped the glyph.
	local textOptions = {
		text = "0",
		x = 0,
		y = 0,
		font = Constants.FONT,
		fontSize = fontSize,
	}
	local text = display.newText(textOptions)
	counter:insert(text)
	text.anchorX = 1
	text.x = frameRight - FRAME_PADDING * pixel
	Font.centerCapsOn(text, centerY, fontSize)
	text:setFillColor(0.2, 0.2, 0.2)

	local function refresh()
		local count = tostring(Garden.getCollectedCount())
		if frame and text.text == count then
			return
		end
		text.text = count
		icon.x = text.x - text.width - ICON_TEXT_GAP * pixel - iconWidth
		if frame then
			frame:removeSelf()
		end
		local width = Frame.snap(frameRight - icon.x + (FRAME_PADDING + 0.5) * pixel, pixel)
		frame = Frame.new(counter, frameRight - width, buttonRect.minY, width, buttonRect.size, "frame", pixel)
		frame:toBack()
	end
	refresh()
	Runtime:addEventListener("enterFrame", refresh)
end

return Hud
