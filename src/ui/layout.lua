local Constants = require("src.util.constants")

-- The play area and the two UI bands below it (CONTEXT.md, ADR-0031): the
-- garden on top, then the HUD band, then the toolbar band at the bottom.
-- The bands are sized to their contents; the garden takes the rest.
local Layout = {}

local SIDE_MARGIN_FRACTION = 0.02
-- Walkable space kept above the HUD band.
local BOTTOM_CLEARANCE = 2 * Constants.PIXEL_SCALE
local TOOLBAR_HEIGHT = (19 + 2 * 2) * Constants.PIXEL_SCALE -- a slot plus a small margin

-- The HUD (counters, shop and barn buttons, the views' close button) is a
-- fixed HUD_PIXELS tall at world scale (ADR-0025).
Layout.HUD_PIXELS = 13 -- the barn button: 9x9 icon, 1px cream, 1px outline
local HUD_MARGIN = 6 * Constants.PIXEL_SCALE -- from the band's right edge
local HUD_GAP_ABOVE = 1 * Constants.PIXEL_SCALE
local HUD_GAP_BELOW = 1 * Constants.PIXEL_SCALE -- above the toolbar's band
-- The top edge the garden and the views' top HUD share: this far below the
-- screen's top, or beside a notch. A top inset above NOTCHLESS_INSET is a
-- notch or island, not just a status bar; those reach about 81% down it.
local TOP_GAP = 2 * Constants.PIXEL_SCALE
local NOTCHLESS_INSET = 30
local NOTCH_SHARE = 0.82

local function toDevicePixel(value)
	return math.floor(value * Constants.DEVICE_SCALE + 0.5) / Constants.DEVICE_SCALE
end

-- Beside a notch or island rather than below it, so the garden reaches up
-- into the space around it (ADR-0031).
local function getTopEdge()
	local topInset = display.getSafeAreaInsets()
	local top = display.screenOriginY + TOP_GAP
	if topInset > NOTCHLESS_INSET then
		top = top + topInset * NOTCH_SHARE
	end
	return toDevicePixel(top)
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

-- Bottom up: the toolbar band, the HUD band on it, and the garden above.
local function computeBands()
	local safeRect = getSafeRect()
	local sideMargin = (safeRect.maxX - safeRect.minX) * SIDE_MARGIN_FRACTION
	local hudSize = Layout.HUD_PIXELS * Constants.PIXEL_SCALE

	local toolbarTop = safeRect.maxY - TOOLBAR_HEIGHT
	local hudBottom = toDevicePixel(toolbarTop - HUD_GAP_BELOW)
	local hudTop = hudBottom - hudSize
	local hudBandTop = hudTop - HUD_GAP_ABOVE

	return {
		playRect = {
			minX = safeRect.minX + sideMargin,
			maxX = safeRect.maxX - sideMargin,
			minY = getTopEdge(),
			maxY = hudBandTop - BOTTOM_CLEARANCE,
		},
		hudBandRect = { minX = safeRect.minX, maxX = safeRect.maxX, minY = hudBandTop, maxY = toolbarTop, hudTop = hudTop },
		bottomBandRect = { minX = safeRect.minX, maxX = safeRect.maxX, minY = toolbarTop, maxY = safeRect.maxY },
	}
end

-- Where world objects may move and be placed. The bottom stops
-- BOTTOM_CLEARANCE short of the HUD band.
function Layout.getPlayArea()
	local rect = computeBands().playRect
	return { minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY }
end

-- The barn button's square, plus pixel: the HUD's content size per art px.
-- The rest of the HUD lines up to its left.
function Layout.getHudRect()
	local band = computeBands().hudBandRect
	local pixel = Constants.PIXEL_SCALE
	local size = Layout.HUD_PIXELS * pixel
	local maxX = toDevicePixel(band.maxX - HUD_MARGIN)
	return { minX = maxX - size, maxX = maxX, minY = band.hudTop, maxY = band.hudTop + size, size = size, pixel = pixel }
end

-- The same square in the shop and barn views, which keep the HUD at the
-- screen's top (ADR-0031).
function Layout.getViewHudRect()
	local rect = Layout.getHudRect()
	local top = getTopEdge()
	rect.minY, rect.maxY = top, top + rect.size
	return rect
end

-- The toolbar's band, at the bottom; also where a fixture or treat is dropped to take it back.
function Layout.getBottomBandRect()
	return computeBands().bottomBandRect
end

return Layout
