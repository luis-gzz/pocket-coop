local Constants = require("src.constants")

-- The two fixed-height UI bands above and below the island (CONTEXT.md,
-- ADR-0008): the egg counter on top, the toolbar on the bottom. Both a fixed
-- native size, like every other piece of UI, rather than a fraction of the
-- screen, so their content always fits regardless of device aspect ratio.
local Layout = {}

Layout.TOP_BAND_HEIGHT = 15 * Constants.PIXEL_SCALE
Layout.BOTTOM_BAND_HEIGHT = 20 * Constants.PIXEL_SCALE

local function getSafeRect()
	local topInset, leftInset, bottomInset, rightInset = display.getSafeAreaInsets()
	return {
		minX = display.screenOriginX + leftInset,
		maxX = display.screenOriginX + display.actualContentWidth - rightInset,
		minY = display.screenOriginY + topInset,
		maxY = display.screenOriginY + display.actualContentHeight - bottomInset,
	}
end

function Layout.getTopBandRect()
	local safeRect = getSafeRect()
	return {
		minX = safeRect.minX,
		maxX = safeRect.maxX,
		minY = safeRect.minY,
		maxY = safeRect.minY + Layout.TOP_BAND_HEIGHT,
	}
end

function Layout.getBottomBandRect()
	local safeRect = getSafeRect()
	return {
		minX = safeRect.minX,
		maxX = safeRect.maxX,
		minY = safeRect.maxY - Layout.BOTTOM_BAND_HEIGHT,
		maxY = safeRect.maxY,
	}
end

-- The safe area with both bands carved out - what src/island.lua fits
-- itself into instead of the raw safe area, so the island never draws
-- underneath either band (ADR-0008).
function Layout.getIslandSafeRect()
	local safeRect = getSafeRect()
	return {
		minX = safeRect.minX,
		maxX = safeRect.maxX,
		minY = safeRect.minY + Layout.TOP_BAND_HEIGHT,
		maxY = safeRect.maxY - Layout.BOTTOM_BAND_HEIGHT,
	}
end

return Layout
