local Constants = require("src.util.constants")
local YSort = require("src.systems.y_sort")
local Tooltip = require("src.ui.tooltip")

-- The view side of a lettuce (CONTEXT.md's Food source). Feed owns the item
-- record and placement rules; this owns the display object and attaches the
-- updateVisual/destroyView closures Feed calls directly on that record.
local Lettuce = {}

local IMAGE_PATH = "assets/objects/lettuce.png"
local NATIVE_WIDTH, NATIVE_HEIGHT = 16, 9
-- Lettuce visibly shrinks toward this floor as it's eaten down, rather than
-- vanishing all at once like the seed patch's scatter does.
local MIN_SCALE = 0.4
-- Share of the leaf's narrowest width a peck point may land in.
local PECK_SPAN = 0.6
-- Sorts just behind a chicken standing at the same depth to peck it.
local DEPTH_BIAS = 0.5

Lettuce.WIDTH = NATIVE_WIDTH * Constants.PIXEL_SCALE
Lettuce.HEIGHT = NATIVE_HEIGHT * Constants.PIXEL_SCALE
Lettuce.CAPACITY = 200 -- food units (src/systems/tuning.lua): ~2 fed-chicken-hours
Lettuce.DESCRIPTOR = { icon = IMAGE_PATH, width = Lettuce.WIDTH, height = Lettuce.HEIGHT, type = "lettuce" }

-- item: { kind="source", type="lettuce", x, y, width, height, capacity,
-- remaining } owned by Feed. A single sprite, anchored at its bottom edge so
-- shrinking reads as being eaten down. Depth-sorted by that bottom edge.
function Lettuce.new(item)
	local width = Lettuce.WIDTH
	local sprite = display.newImageRect(IMAGE_PATH, width, Lettuce.HEIGHT)
	YSort.getGroup():insert(sprite)
	sprite.anchorY = 1
	sprite.x = item.x
	sprite.y = item.y + Lettuce.HEIGHT / 2
	YSort.add(sprite, function(view)
		return view.y - DEPTH_BIAS
	end)

	function item.updateVisual()
		local fraction = item.remaining / item.capacity
		local scale = MIN_SCALE + (1 - MIN_SCALE) * fraction
		sprite.xScale = scale
		sprite.yScale = scale
	end
	item.updateVisual()

	-- Drawn from the fully-shrunk width, so the beak stays on the leaf, and on
	-- the half nearer a chicken facing `facing` toward it, so it doesn't cover it.
	function item.pickPeckPoint(facing)
		local span = width * MIN_SCALE * PECK_SPAN
		return { x = item.x - facing * math.random() * span / 2, y = sprite.y }
	end

	function item.destroyView()
		YSort.remove(sprite)
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
