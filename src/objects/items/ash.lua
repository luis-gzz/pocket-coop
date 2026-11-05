local Constants = require("src.util.constants")
local TreatView = require("src.objects.items.treat_view")
local Gauges = require("src.objects.chicken.gauges")
local HappinessIcon = require("src.ui.happiness_icon")

-- Ash (CONTEXT.md): the early-game treat that bumps cleanliness, drawn as
-- an ash patch in the floor layer. Treats owns the item record.
local Ash = {}

local IMAGE_PATH = "assets/objects/ash.png"
local ICON_PATH = "assets/objects/ash_icon.png"
local NATIVE_WIDTH, NATIVE_HEIGHT = 25, 10

Ash.WIDTH = NATIVE_WIDTH * Constants.PIXEL_SCALE
Ash.HEIGHT = NATIVE_HEIGHT * Constants.PIXEL_SCALE
Ash.GAUGE = "cleanliness"
Ash.AMOUNT = 75
-- The toolbar shows the 16x16 icon rather than the wide patch.
Ash.DESCRIPTOR = {
	icon = ICON_PATH,
	iconWidth = 16,
	iconHeight = 16,
	width = Ash.WIDTH,
	height = Ash.HEIGHT,
	type = "ash", name = "Ash bath",
}

local TOOLTIP = {
	title = "Ash bath",
	rows = {
		{ icon = "assets/objects/sparkle.png", text = "+" .. Ash.AMOUNT },
		{ icon = HappinessIcon.HAPPY, text = "+" .. Gauges.HAPPINESS_BUFF_AMOUNT },
	},
}

function Ash.new(item, resolveDrop)
	return TreatView.new(item, { image = IMAGE_PATH, floor = true, tooltip = TOOLTIP }, resolveDrop)
end

return Ash
