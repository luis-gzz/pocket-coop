local Constants = require("src.util.constants")
local YSort = require("src.systems.y_sort")
local Tooltip = require("src.ui.tooltip")
local Shadow = require("src.objects.shadow")

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
-- remaining } owned by Feed. A group at the lettuce's bottom edge, so
-- shrinking it (sprite and shadow) reads as being eaten down. Depth-sorted by that edge.
function Lettuce.new(item)
	local width = Lettuce.WIDTH
	local view = display.newGroup()
	YSort.getGroup():insert(view)
	view.x = item.x
	view.y = item.y + Lettuce.HEIGHT / 2
	YSort.add(view, function(object)
		return object.y - DEPTH_BIAS
	end)
	Shadow.new(view, NATIVE_WIDTH)
	local sprite = display.newImageRect(view, IMAGE_PATH, width, Lettuce.HEIGHT)
	sprite.anchorY = 1

	function item.updateVisual()
		local fraction = item.remaining / item.capacity
		local scale = MIN_SCALE + (1 - MIN_SCALE) * fraction
		view.xScale = scale
		view.yScale = scale
	end
	item.updateVisual()

	-- Drawn from the fully-shrunk width, so the beak stays on the leaf, and on
	-- the half nearer a chicken facing `facing` toward it, so it doesn't cover it.
	function item.pickPeckPoint(facing)
		local span = width * MIN_SCALE * PECK_SPAN
		return { x = item.x - facing * math.random() * span / 2, y = view.y }
	end

	function item.destroyView()
		YSort.remove(view)
		view:removeSelf()
	end

	sprite:addEventListener("tap", function()
		Tooltip.show({
			source = item,
			x = item.x,
			y = item.y,
			rows = {
				{ label = "Lettuce", getValue = function() return item.remaining / item.capacity * 100 end },
			},
		})
		return true
	end)

	return view
end

return Lettuce
