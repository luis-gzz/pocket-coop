local Constants = require("src.util.constants")
local Layout = require("src.ui.layout")
local Font = require("src.ui.font")
local Garden = require("src.systems.garden")
local Slot = require("src.ui.slot")
local BarnView = require("src.ui.barn_view")
local DropZone = require("src.ui.drop_zone")

-- The top UI band's at-a-glance stat displays - the egg counter (the
-- player's total collected eggs, their stash, not the number of eggs
-- currently sitting uncollected in the world - see CONTEXT.md) - and the
-- barn button at its right, which opens the barn view.
local Hud = {}

local ICON_NATIVE_WIDTH, ICON_NATIVE_HEIGHT = 6, 7
local ICON_WIDTH = ICON_NATIVE_WIDTH * Constants.PIXEL_SCALE
local ICON_HEIGHT = ICON_NATIVE_HEIGHT * Constants.PIXEL_SCALE
local ICON_TEXT_GAP = 5 * Constants.PIXEL_SCALE
local BUTTON_GAP = 6 * Constants.PIXEL_SCALE

local ICON_PATH = "assets/fauna/ChickenEgg.png"

function Hud.create()
	local band = Layout.getTopBandRect()
	local centerY = (band.minY + band.maxY) / 2

	local buttonRect = Layout.getHudButtonRect(Slot.SIZE)
	local barnButton = Slot.new(display.getCurrentStage(), buttonRect.minX, buttonRect.minY, nil, buttonRect.size,
		Slot.BUTTON_CORNER_RADIUS)
	Slot.drawBarnIcon(barnButton, buttonRect.size)
	barnButton.background:addEventListener("tap", function()
		BarnView.show()
		return true
	end)
	DropZone.onLanded(function(area)
		if area == "barn" then
			barnButton.flash()
		end
	end)

	local icon = display.newImageRect(ICON_PATH, ICON_WIDTH, ICON_HEIGHT)
	icon.anchorX = 1
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
		fontSize = Constants.FONT_SIZE_LARGE,
	}
	local text = display.newText(textOptions)
	text.anchorX = 1
	text.x = barnButton.x - BUTTON_GAP
	Font.centerCapsOn(text, centerY, Constants.FONT_SIZE_LARGE)
	text:setFillColor(0.2, 0.2, 0.2)

	local function refresh()
		text.text = tostring(Garden.getCollectedCount())
		icon.x = text.x - text.width - ICON_TEXT_GAP
	end
	refresh()
	Runtime:addEventListener("enterFrame", refresh)
end

return Hud
