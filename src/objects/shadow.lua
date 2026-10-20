local Constants = require("src.util.constants")
local Color = require("src.util.color")

-- The shadow every non-flat world object casts (CONTEXT.md's Shadow): a rounded
-- rect for items and fixtures, an oval for the chicken. New standing objects should add one.
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

-- One rect per row; spans[i] is row i's width in native px. Centered on the
-- group's origin - place it at the caster's bottom-center.
local function newRows(parent, spans, unit)
	local group = display.newGroup()
	parent:insert(group)
	group.alpha = ALPHA
	local r, g, b = Color.hexToRGB(FILL_HEX)
	for row, span in ipairs(spans) do
		local y = (row - 0.5 - #spans / 2) * unit
		display.newRect(group, 0, y, span * unit, unit):setFillColor(r, g, b)
	end
	return group
end

-- A 4px-high rounded rect sized from the caster's native width. unit: points
-- per native pixel (default PIXEL_SCALE; 1 inside an already-scaled group).
function Shadow.new(parent, casterNativeWidth, unit)
	local width = math.max(2, casterNativeWidth)
	return newRows(parent, { width - 2, width, width, width - 2 }, unit or Constants.PIXEL_SCALE)
end

-- The pixel-crisp oval (the chicken); same arguments as Shadow.new.
function Shadow.newOval(parent, casterNativeWidth, unit)
	local width = casterNativeWidth - 1
	local height = math.max(3, math.floor(width / 3 + 0.5))
	local spans = {}
	for row = 0, height - 1 do
		local t = (row + 0.5 - height / 2) / (height / 2)
		spans[#spans + 1] = rowWidth(width * math.sqrt(1 - t * t), width)
	end
	return newRows(parent, spans, unit or Constants.PIXEL_SCALE)
end

return Shadow
