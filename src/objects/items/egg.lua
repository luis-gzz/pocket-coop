local Constants = require("src.util.constants")
local YSort = require("src.systems.y_sort")
local Shadow = require("src.objects.shadow")

-- The view side of an egg (CONTEXT.md) - either sitting in a hen bed or on
-- the ground as a floor egg. Garden owns the { bed, view, x, y } records and
-- decides collection; this owns the display object and turning a tap into a
-- collect.
local Egg = {}

local IMAGE_PATH = "assets/fauna/ChickenEgg.png"
local NATIVE_WIDTH, NATIVE_HEIGHT = 7, 8

Egg.WIDTH = NATIVE_WIDTH * Constants.PIXEL_SCALE
Egg.HEIGHT = NATIVE_HEIGHT * Constants.PIXEL_SCALE
-- Invisible tap margin around the sprite, for fingers bigger than the egg.
local TAP_PADDING = 4 * Constants.PIXEL_SCALE

-- The egg sprite in a group with a padded, invisible hit rect (and a shadow,
-- if withShadow); taps on either call onTap.
local function newTappable(parent, onTap, withShadow)
	local group = display.newGroup()
	parent:insert(group)
	local hitArea = display.newRect(group, 0, 0, Egg.WIDTH + TAP_PADDING * 2, Egg.HEIGHT + TAP_PADDING * 2)
	hitArea.isVisible = false
	hitArea.isHitTestable = true
	if withShadow then
		Shadow.new(group, NATIVE_WIDTH).y = Egg.HEIGHT / 2
	end
	display.newImageRect(group, IMAGE_PATH, Egg.WIDTH, Egg.HEIGHT)
	group:addEventListener("tap", function()
		onTap()
		return true
	end)
	return group
end

-- A floor egg: its own YSort-registered image at (x, y). onTap() is called
-- when tapped, so the caller (Garden) can collect it.
function Egg.newFloor(x, y, onTap)
	local view = newTappable(YSort.getGroup(), onTap, true)
	view.x = x
	view.y = y
	YSort.add(view, function(object)
		return object.y + Egg.HEIGHT / 2
	end)
	return view
end

-- An egg sitting inside a bed's own display group, sharing the bed's shadow (see bed.lua) - inserting
-- into it means the egg moves for free when the bed is dragged. offsetX
-- (already scaled) places it in one of the bed's egg slots (Bed.getSlotOffsetX);
-- anchored so its bottom edge, not its center, sits at the bed's vertical
-- center, reading as sitting in the nest rather than floating above it.
-- onTap() is called when tapped, so the caller (Garden) can collect it.
function Egg.newInBed(bedGroup, offsetX, onTap)
	local view = newTappable(bedGroup, onTap)
	view.x = offsetX
	view.y = -Egg.HEIGHT / 2
	return view
end

return Egg
