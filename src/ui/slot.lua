local Constants = require("src.util.constants")
local Color = require("src.util.color")

-- The fixed-size square behind an item's icon (CONTEXT.md's Slot), shared by
-- the toolbar and the barn panel.
local Slot = {}

-- Every item gets the same fixed-size square slot regardless of its own
-- icon's dimensions - the icon inside is scaled down to fit (see wholeFit).
-- The bottom band's height is derived from the play area's leftover space
-- (ADR-0009), not fixed, so this is sized to comfortably fit within it.
Slot.SIZE = 19 * Constants.PIXEL_SCALE
local PADDING = 2 * Constants.PIXEL_SCALE

-- Same visual language as tooltip.lua's panel (fill/stroke/corner radius).
local FILL_HEX = "f2f0e5"
local STROKE_HEX = "3a3858"
local SELECTED_STROKE_HEX = "4b80ca"
local CORNER_RADIUS = 3 * Constants.PIXEL_SCALE
local STROKE_WIDTH = 1 * Constants.PIXEL_SCALE
local SELECTED_STROKE_WIDTH = 2 * Constants.PIXEL_SCALE

-- Fits an item's icon into a square box of availableSize at a whole number
-- of screen pixels per art pixel, never above world size (ADR-0020). Native
-- size is iconWidth/Height if given, else the world size over PIXEL_SCALE.
local function wholeFit(item, availableSize)
	local nativeWidth = item.iconWidth or math.floor(item.width / Constants.PIXEL_SCALE + 0.5)
	local nativeHeight = item.iconHeight or math.floor(item.height / Constants.PIXEL_SCALE + 0.5)
	local ppa = math.min(
		Constants.WORLD_PPA,
		Constants.snapPpa(availableSize * Constants.DEVICE_SCALE, math.max(nativeWidth, nativeHeight))
	)
	local unit = ppa / Constants.DEVICE_SCALE
	return nativeWidth * unit, nativeHeight * unit
end

-- A slot group with its top-left at (x, y). item (optional) is a catalog
-- descriptor whose icon is drawn inside. Returns the group; its .background
-- takes touch/tap listeners and setSelected(bool) toggles the highlight.
function Slot.new(parent, x, y, item)
	local group = display.newGroup()
	parent:insert(group)
	group.x, group.y = x, y

	local background = display.newRoundedRect(group, Slot.SIZE / 2, Slot.SIZE / 2, Slot.SIZE, Slot.SIZE, CORNER_RADIUS)
	background:setFillColor(Color.hexToRGB(FILL_HEX))
	group.background = background

	if item then
		local width, height = wholeFit(item, Slot.SIZE - PADDING * 2)
		local icon = display.newImageRect(group, item.icon, width, height)
		icon.x, icon.y = Slot.SIZE / 2, Slot.SIZE / 2
	end

	function group.setSelected(selected)
		background.strokeWidth = selected and SELECTED_STROKE_WIDTH or STROKE_WIDTH
		background:setStrokeColor(Color.hexToRGB(selected and SELECTED_STROKE_HEX or STROKE_HEX))
	end
	group.setSelected(false)

	return group
end

return Slot
