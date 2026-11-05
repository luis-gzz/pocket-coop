local Constants = require("src.util.constants")
local Color = require("src.util.color")

-- The fixed-size square behind an item's icon (CONTEXT.md's Slot), shared by
-- the toolbar, the barn view, and the HUD's barn button.
local Slot = {}

-- Every item gets the same fixed-size square slot regardless of its own
-- icon's dimensions - the icon inside is scaled down to fit (see wholeFit).
-- The bottom band's height is derived from the play area's leftover space
-- (ADR-0009), not fixed, so this is sized to comfortably fit within it.
Slot.SIZE = 19 * Constants.PIXEL_SCALE
local PADDING = 2 * Constants.PIXEL_SCALE

-- Same visual language as tooltip.lua's panel (fill/stroke/corner radius).
-- Every colour is from the palette (assets/colorway.png).
local FILL_HEX = "f2f0e5"
local STROKE_HEX = "3a3858"
local SELECTED_STROKE_HEX = "4b80ca"
local CORNER_RADIUS = 3 * Constants.PIXEL_SCALE
-- Tighter corners for the top band's buttons (the barn button, the barn view's close button).
Slot.BUTTON_CORNER_RADIUS = 2 * Constants.PIXEL_SCALE
local STROKE_WIDTH = 1 * Constants.PIXEL_SCALE
local SELECTED_STROKE_WIDTH = 2 * Constants.PIXEL_SCALE
local FLASH_TIME = 600 -- ms

-- Fits an item's icon into a square box of availableSize at a whole number
-- of screen pixels per art pixel, never above world size (ADR-0020). Native
-- size is iconWidth/Height if given, else the world size over PIXEL_SCALE.
function Slot.fitIcon(item, availableSize)
	local nativeWidth = item.iconWidth or math.floor(item.width / Constants.PIXEL_SCALE + 0.5)
	local nativeHeight = item.iconHeight or math.floor(item.height / Constants.PIXEL_SCALE + 0.5)
	local ppa = math.min(
		Constants.WORLD_PPA,
		Constants.snapPpa(availableSize * Constants.DEVICE_SCALE, math.max(nativeWidth, nativeHeight))
	)
	local unit = ppa / Constants.DEVICE_SCALE
	return nativeWidth * unit, nativeHeight * unit
end

-- An item's icon fitted inside a slot of the given size, centered on (x, y).
function Slot.newIcon(parent, item, x, y, size)
	local width, height = Slot.fitIcon(item, (size or Slot.SIZE) - PADDING * 2)
	local icon = display.newImageRect(parent, item.icon, width, height)
	icon.x, icon.y = x, y
	return icon
end

-- The barn button's 16x16 icon, filling about this share of the button
-- (snapped down to whole screen pixels per art pixel, ADR-0020).
local BARN_ICON = { icon = "assets/objects/barn_icon.png", iconWidth = 16, iconHeight = 16 }
local BARN_ICON_SHARE = 0.8

function Slot.drawBarnIcon(group, size)
	size = size or Slot.SIZE
	local width, height = Slot.fitIcon(BARN_ICON, size * BARN_ICON_SHARE)
	local icon = display.newImageRect(group, BARN_ICON.icon, width, height)
	icon.x, icon.y = size / 2, size / 2
	return icon
end

-- A slot group with its top-left at (x, y), size defaulting to Slot.SIZE
-- and cornerRadius to a slot's.
-- item (optional) is a catalog descriptor whose icon is drawn inside, kept
-- as .icon. Its .background takes touch/tap listeners; setSelected(bool)
-- toggles the highlight and flash() pulses it once.
function Slot.new(parent, x, y, item, size, cornerRadius)
	size = size or Slot.SIZE
	local group = display.newGroup()
	parent:insert(group)
	group.x, group.y = x, y

	local background = display.newRoundedRect(group, size / 2, size / 2, size, size, cornerRadius or CORNER_RADIUS)
	background:setFillColor(Color.hexToRGB(FILL_HEX))
	group.background = background

	if item then
		group.icon = Slot.newIcon(group, item, size / 2, size / 2, size)
	end

	local selected = false
	local flashing = false
	local function refresh()
		local lit = selected or flashing
		background.strokeWidth = lit and SELECTED_STROKE_WIDTH or STROKE_WIDTH
		background:setStrokeColor(Color.hexToRGB(lit and SELECTED_STROKE_HEX or STROKE_HEX))
	end

	function group.setSelected(isSelected)
		selected = isSelected
		refresh()
	end

	function group.flash()
		flashing = true
		refresh()
		timer.performWithDelay(FLASH_TIME, function()
			if group.removeSelf then
				flashing = false
				refresh()
			end
		end)
	end

	refresh()
	return group
end

return Slot
