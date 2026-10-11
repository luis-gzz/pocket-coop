local Constants = require("src.util.constants")
local Color = require("src.util.color")

-- The oval every non-flat world object casts (CONTEXT.md's Shadow). A new
-- world object that stands up off the ground should add one with Shadow.new.
local Shadow = {}

local FILL_HEX = "212123"
local ALPHA = 0.2

-- Rounds to the nearest integer with the same parity as width, so each row
-- stays centered on the pixel grid.
local function rowWidth(exact, width)
	local rounded = math.floor(exact + 0.5)
	if rounded % 2 ~= width % 2 then
		rounded = (exact > rounded) and rounded + 1 or rounded - 1
	end
	return math.max(1, rounded)
end

-- A pixel-crisp oval sized from the caster's native width, centered on the
-- group's origin - place it at the caster's bottom-center. unit: points per native pixel
-- (default PIXEL_SCALE; 1 inside an already-scaled group).
function Shadow.new(parent, casterNativeWidth, unit)
	unit = unit or Constants.PIXEL_SCALE
	local width = casterNativeWidth - 1
	local height = math.max(3, math.floor(width / 3 + 0.5))

	local group = display.newGroup()
	parent:insert(group)
	group.alpha = ALPHA
	local r, g, b = Color.hexToRGB(FILL_HEX)
	for row = 0, height - 1 do
		local t = (row + 0.5 - height / 2) / (height / 2)
		local span = rowWidth(width * math.sqrt(1 - t * t), width)
		local rect = display.newRect(group, 0, (row + 0.5 - height / 2) * unit, span * unit, unit)
		rect:setFillColor(r, g, b)
	end
	return group
end

return Shadow
