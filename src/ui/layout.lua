local Constants = require("src.util.constants")

-- The play area and the two UI bands above/below it (CONTEXT.md, ADR-0009,
-- ADR-0017, ADR-0025). The top band just fits the HUD; the bottom band gets the rest.
local Layout = {}

local TILE_SIZE = Constants.TILE_SIZE

local HEIGHT_FRACTION = 0.85
local SIDE_MARGIN_FRACTION = 0.02
-- Walkable space kept above the bottom band.
local BOTTOM_CLEARANCE = 2 * Constants.PIXEL_SCALE

-- The HUD (barn button, egg counter, barn view's close button) is a fixed
-- HUD_PIXELS tall at world scale, scaled down whole only if that won't fit (ADR-0025).
Layout.HUD_PIXELS = 13 -- the barn button: 9x9 icon, 1px cream, 1px outline
local HUD_MARGIN = 6 * Constants.PIXEL_SCALE -- from the band's right edge
local HUD_TOP_GAP = 2 * Constants.PIXEL_SCALE
local HUD_BOTTOM_GAP = 1 * Constants.PIXEL_SCALE -- kept clear above the play area
-- A top inset above this is a notch or island, not just a status bar; those
-- reach about 81% down it (Dynamic Island: 48 of 59pt).
local NOTCHLESS_INSET = 30
local NOTCH_SHARE = 0.82

local function toDevicePixel(value)
	return math.floor(value * Constants.DEVICE_SCALE + 0.5) / Constants.DEVICE_SCALE
end

local function getSafeRect()
	local topInset, leftInset, bottomInset, rightInset = display.getSafeAreaInsets()
	return {
		minX = display.screenOriginX + leftInset,
		maxX = display.screenOriginX + display.actualContentWidth - rightInset,
		minY = display.screenOriginY + topInset,
		maxY = display.screenOriginY + display.actualContentHeight - bottomInset,
	}
end

-- Where the HUD's top edge sits: a small gap below the screen's top, or below a notch.
local function getHudTop()
	local topInset = display.getSafeAreaInsets()
	local top = display.screenOriginY + HUD_TOP_GAP
	if topInset > NOTCHLESS_INSET then
		top = top + topInset * NOTCH_SHARE
	end
	return toDevicePixel(top)
end

-- The walkable height is the play area's HEIGHT_FRACTION share less half a tile,
-- as before; it starts just under the HUD, clamped so it still clears the toolbar.
local function computeBands()
	local safeRect = getSafeRect()
	local safeWidth = safeRect.maxX - safeRect.minX
	local walkHeight = (safeRect.maxY - safeRect.minY) * HEIGHT_FRACTION - TILE_SIZE / 2
	local sideMargin = safeWidth * SIDE_MARGIN_FRACTION
	local toolbarHeight = (19 + 2 * 2) * Constants.PIXEL_SCALE -- a slot plus a small margin

	local hudBottom = getHudTop() + Layout.HUD_PIXELS * Constants.PIXEL_SCALE + HUD_BOTTOM_GAP
	local latestTop = safeRect.maxY - toolbarHeight - BOTTOM_CLEARANCE - walkHeight
	local playMinY = math.max(safeRect.minY, math.min(hudBottom, latestTop))
	local walkMaxY = playMinY + walkHeight

	return {
		playRect = {
			minX = safeRect.minX + sideMargin,
			maxX = safeRect.maxX - sideMargin,
			minY = playMinY,
			maxY = walkMaxY,
		},
		topBandRect = { minX = safeRect.minX, maxX = safeRect.maxX, minY = safeRect.minY, maxY = playMinY },
		bottomBandRect = {
			minX = safeRect.minX, maxX = safeRect.maxX, minY = walkMaxY + BOTTOM_CLEARANCE, maxY = safeRect.maxY,
		},
	}
end

-- Where world objects may move and be placed. The bottom stops
-- BOTTOM_CLEARANCE short of the bottom band.
function Layout.getPlayArea()
	local rect = computeBands().playRect
	return { minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY }
end

function Layout.getTopBandRect()
	return computeBands().topBandRect
end

-- The barn button's square, plus pixel: the HUD's content size per art px.
function Layout.getHudRect()
	local band = computeBands().topBandRect
	local top = getHudTop()
	local ppa = math.floor((band.maxY - HUD_BOTTOM_GAP - top) * Constants.DEVICE_SCALE / Layout.HUD_PIXELS)
	ppa = math.max(1, math.min(Constants.WORLD_PPA, ppa))
	local pixel = ppa / Constants.DEVICE_SCALE
	local size = Layout.HUD_PIXELS * pixel
	local maxX = toDevicePixel(band.maxX - HUD_MARGIN)
	return { minX = maxX - size, maxX = maxX, minY = top, maxY = top + size, size = size, pixel = pixel }
end

function Layout.getBottomBandRect()
	return computeBands().bottomBandRect
end

return Layout
