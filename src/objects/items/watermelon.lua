local Constants = require("src.util.constants")
local TreatView = require("src.objects.items.treat_view")
local Gauges = require("src.objects.chicken.gauges")
local HappinessIcon = require("src.ui.happiness_icon")

-- A watermelon slice (CONTEXT.md): a treat that gives hydration. Treats owns the item
-- record; TreatView owns the sprite and drag.
local Watermelon = {}

local IMAGE_PATH = "assets/objects/watermelon.png"
local NATIVE_WIDTH, NATIVE_HEIGHT = 12, 8

Watermelon.WIDTH = NATIVE_WIDTH * Constants.PIXEL_SCALE
Watermelon.HEIGHT = NATIVE_HEIGHT * Constants.PIXEL_SCALE
-- The gauge this treat helps and by how much - read by alert priority and
-- the payoff.
Watermelon.GAUGE = "hydration"
Watermelon.AMOUNT = 50
Watermelon.DESCRIPTOR = { icon = IMAGE_PATH, width = Watermelon.WIDTH, height = Watermelon.HEIGHT, type = "watermelon" }

-- Share of the slice's width a peck point may land in.
local PECK_SPAN = 0.6
-- Sorts just behind a chicken standing at the same depth to peck it.
local DEPTH_BIAS = 0.5

local TOOLTIP = {
	title = "Watermelon slice",
	rows = {
		{ icon = "assets/objects/water_drop.png", text = "+" .. Watermelon.AMOUNT },
		{ icon = HappinessIcon.HAPPY, text = "+" .. Gauges.HAPPINESS_BUFF_AMOUNT },
	},
}

function Watermelon.new(item, resolveDrop)
	local view = TreatView.new(
		item,
		{ image = IMAGE_PATH, depthBias = DEPTH_BIAS, shadow = NATIVE_WIDTH, tooltip = TOOLTIP },
		resolveDrop
	)

	-- On the half nearer a chicken facing `facing` toward the slice, so it doesn't cover it.
	function item.pickPeckPoint(facing)
		return { x = item.x - facing * math.random() * item.width * PECK_SPAN / 2, y = item.y + item.height / 2 }
	end

	return view
end

return Watermelon
