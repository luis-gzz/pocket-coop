local Constants = require("src.util.constants")
local YSort = require("src.systems.y_sort")

-- The view side of an egg (CONTEXT.md) - either sitting in a hen bed or on
-- the ground as a floor egg. Garden owns the { bed, view, x, y } records and
-- decides collection; this owns the display object and turning a tap into a
-- collect.
local Egg = {}

local IMAGE_PATH = "assets/fauna/ChickenEgg.png"
local NATIVE_WIDTH, NATIVE_HEIGHT = 7, 8

Egg.WIDTH = NATIVE_WIDTH * Constants.PIXEL_SCALE
Egg.HEIGHT = NATIVE_HEIGHT * Constants.PIXEL_SCALE

-- A floor egg: its own YSort-registered image at (x, y). onTap() is called
-- when tapped, so the caller (Garden) can collect it.
function Egg.newFloor(x, y, onTap)
	local image = display.newImageRect(IMAGE_PATH, Egg.WIDTH, Egg.HEIGHT)
	YSort.getGroup():insert(image)
	image.x = x
	image.y = y
	YSort.add(image, function(view)
		return view.y + Egg.HEIGHT / 2
	end)
	image:addEventListener("tap", function()
		onTap()
		return true
	end)
	return image
end

-- An egg sitting inside a bed's own display group (see bed.lua) - inserting
-- into it means the egg moves for free when the bed is dragged. Anchored so
-- its bottom edge, not its center, sits at the bed's center point, reading
-- as sitting in the nest rather than floating above it. onTap() is called
-- when tapped, so the caller (Garden) can collect it.
function Egg.newInBed(bedGroup, onTap)
	local image = display.newImageRect(bedGroup, IMAGE_PATH, Egg.WIDTH, Egg.HEIGHT)
	image.x = 0
	image.y = -Egg.HEIGHT / 2
	image:addEventListener("tap", function()
		onTap()
		return true
	end)
	return image
end

return Egg
