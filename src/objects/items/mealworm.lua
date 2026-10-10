local Constants = require("src.util.constants")
local TreatView = require("src.objects.items.treat_view")
local Gauges = require("src.objects.chicken.gauges")

-- A mealworm (CONTEXT.md): a treat that gives satiety. Treats owns the item
-- record; TreatView owns the sprite and drag.
local Mealworm = {}

local IMAGE_PATH = "assets/objects/mealworm.png"
local NATIVE_WIDTH, NATIVE_HEIGHT = 12, 5

Mealworm.WIDTH = NATIVE_WIDTH * Constants.PIXEL_SCALE
Mealworm.HEIGHT = NATIVE_HEIGHT * Constants.PIXEL_SCALE
-- The gauge this treat helps and by how much - read by alert priority and
-- the payoff.
Mealworm.GAUGE = "satiety"
Mealworm.AMOUNT = 25
Mealworm.DESCRIPTOR = { icon = IMAGE_PATH, width = Mealworm.WIDTH, height = Mealworm.HEIGHT, type = "mealworm" }

-- Share of the worm's width a peck point may land in.
local PECK_SPAN = 0.6
-- Sorts just behind a chicken standing at the same depth to peck it.
local DEPTH_BIAS = 0.5

local TOOLTIP = {
	title = "Mealworm",
	rows = {
		{ icon = "assets/objects/carrot.png", text = "+" .. Mealworm.AMOUNT },
		{ icon = "assets/fauna/heart.png", text = "+" .. Gauges.HAPPINESS_BUFF_AMOUNT },
	},
}

function Mealworm.new(item, resolveDrop)
	local sprite = TreatView.new(item, { image = IMAGE_PATH, depthBias = DEPTH_BIAS, tooltip = TOOLTIP }, resolveDrop)

	function item.pickPeckPoint()
		return { x = item.x + (math.random() - 0.5) * item.width * PECK_SPAN, y = item.y + item.height / 2 }
	end

	return sprite
end

return Mealworm
