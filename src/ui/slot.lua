local Constants = require("src.util.constants")
local Frame = require("src.ui.frame")

-- The fixed-size square behind an item's icon (CONTEXT.md's Slot), shared by
-- the toolbar, the barn view, and the HUD's barn button.
local Slot = {}

-- Every item gets the same fixed-size square slot regardless of its own
-- icon's dimensions - the icon inside is scaled down to fit (see wholeFit).
-- The bottom band's height is derived from the play area's leftover space
-- (ADR-0009), not fixed, so this is sized to comfortably fit within it.
Slot.SIZE = 19 * Constants.PIXEL_SCALE
local PADDING = 2 * Constants.PIXEL_SCALE

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

-- An art-pixel icon drawn at a slot's own pixel scale, top-left offsetPixels
-- in, so its pixels line up with the frame's (the HUD's barn and close icons).
function Slot.drawPixelIcon(group, path, iconPixels, offsetPixels, pixel)
	local icon = display.newImageRect(group, path, iconPixels * pixel, iconPixels * pixel)
	icon.anchorX, icon.anchorY = 0, 0
	icon.x, icon.y = offsetPixels * pixel, offsetPixels * pixel
	return icon
end

-- A slot group with its top-left at (x, y), size defaulting to Slot.SIZE
-- (snapped to whole art px). item (optional) is a catalog descriptor whose
-- icon is drawn inside, kept as .icon. Its .background takes touch/tap
-- listeners; setSelected(bool) toggles the highlight, flash() pulses it once.
-- pixel (optional) is the art px size, world-sized by default.
function Slot.new(parent, x, y, item, size, pixel)
	size = Frame.snap(size or Slot.SIZE, pixel)
	local group = display.newGroup()
	parent:insert(group)
	group.x, group.y = x, y

	local background = display.newGroup()
	group:insert(background)
	Frame.new(background, 0, 0, size, size, "frame", pixel)
	local highlight = Frame.new(background, 0, 0, size, size, "selected", pixel)
	group.background = background
	group.size = size

	if item then
		group.icon = Slot.newIcon(group, item, size / 2, size / 2, size)
	end

	local selected = false
	local flashing = false
	local function refresh()
		highlight.isVisible = selected or flashing
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
