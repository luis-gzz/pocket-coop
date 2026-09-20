local Constants = require("src.util.constants")
local YSort = require("src.systems.y_sort")
local Tooltip = require("src.ui.tooltip")

-- The view side of a lettuce (CONTEXT.md's Food source). Feed owns the item
-- record and placement rules; this owns the display object and attaches the
-- updateVisual/destroyView closures Feed calls directly on that record.
local Lettuce = {}

local IMAGE_PATH = "assets/objects/lettuce.png"
local NATIVE_SIZE = 16
-- Lettuce visibly shrinks toward this floor as it's eaten down, rather than
-- vanishing all at once like the seed patch's scatter does.
local MIN_SCALE = 0.4

Lettuce.WIDTH = NATIVE_SIZE * Constants.PIXEL_SCALE
Lettuce.HEIGHT = Lettuce.WIDTH
Lettuce.CAPACITY = 200
Lettuce.DESCRIPTOR = { icon = IMAGE_PATH, width = Lettuce.WIDTH, height = Lettuce.HEIGHT, type = "lettuce" }

-- item: { kind="source", type="lettuce", x, y, width, height, capacity,
-- remaining } owned by Feed. A single sprite, anchored at its bottom edge so
-- shrinking reads as being eaten down. Not registered with YSort - always
-- renders behind.
function Lettuce.new(item)
	local width = Lettuce.WIDTH
	local sprite = display.newImageRect(IMAGE_PATH, width, width)
	YSort.getGroup():insert(sprite)
	sprite.anchorY = 1
	sprite.x = item.x
	sprite.y = item.y + width / 2

	function item.updateVisual()
		local fraction = item.remaining / item.capacity
		local scale = MIN_SCALE + (1 - MIN_SCALE) * fraction
		sprite.xScale = scale
		sprite.yScale = scale
	end
	item.updateVisual()

	function item.destroyView()
		sprite:removeSelf()
	end

	sprite:addEventListener("tap", function()
		Tooltip.show({
			x = item.x,
			y = item.y,
			rows = {
				{ label = "Lettuce", getValue = function() return item.remaining / item.capacity * 100 end },
			},
		})
		return true
	end)

	return sprite
end

return Lettuce
