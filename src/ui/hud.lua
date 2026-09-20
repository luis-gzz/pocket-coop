local Constants = require("src.util.constants")
local Layout = require("src.ui.layout")
local Garden = require("src.systems.garden")

-- The top UI band's at-a-glance stat displays - today just the egg counter
-- (the player's total collected eggs, their stash, not the number of eggs
-- currently sitting uncollected in the world - see CONTEXT.md). Named for
-- the band's general role so a future stat display isn't a rename.
local Hud = {}

local ICON_NATIVE_WIDTH, ICON_NATIVE_HEIGHT = 7, 8
local ICON_WIDTH = ICON_NATIVE_WIDTH * Constants.PIXEL_SCALE
local ICON_HEIGHT = ICON_NATIVE_HEIGHT * Constants.PIXEL_SCALE
local ICON_TEXT_GAP = 5 * Constants.PIXEL_SCALE
local EDGE_MARGIN = 6 * Constants.PIXEL_SCALE
-- Confirmed the egg icon has no transparent padding (its opaque pixels fill
-- the whole canvas), so its anchorY = 0.5 center is exactly its visual
-- center. The text still read as sitting too low against it - Awkward.ttf's
-- box that anchorY = 0.5 centers against apparently reserves more room
-- above a digit's ink than below, so nudge the text up to compensate.
local TEXT_Y_NUDGE = 2 * Constants.PIXEL_SCALE

local ICON_PATH = "assets/fauna/ChickenEgg.png"

function Hud.create()
	local band = Layout.getTopBandRect()
	local centerY = (band.minY + band.maxY) / 2

	local icon = display.newImageRect(ICON_PATH, ICON_WIDTH, ICON_HEIGHT)
	icon.anchorX = 1
	icon.anchorY = 0.5
	icon.y = centerY

	-- No explicit width/height here: constraining newText's box height to
	-- icon.height (much shorter than FONT_SIZE_SMALL's actual line height)
	-- clipped the glyph and threw off its vertical center relative to the
	-- icon. A single-line auto-sized text object centers on its own true
	-- glyph bounds instead, matching icon's anchorY = 0.5 center.
	local textOptions = {
		text = "0",
		x = 0,
		y = 0,
		font = Constants.FONT,
		fontSize = Constants.FONT_SIZE_LARGE,
	}
	local text = display.newText(textOptions)
	text.anchorX = 1
	text.anchorY = 0.5
	text.x = band.maxX - EDGE_MARGIN
	text.y = centerY - TEXT_Y_NUDGE
	text:setFillColor(0.2, 0.2, 0.2)

	local function refresh()
		text.text = tostring(Garden.getCollectedCount())
		icon.x = text.x - text.width - ICON_TEXT_GAP
	end
	refresh()
	Runtime:addEventListener("enterFrame", refresh)
end

return Hud
