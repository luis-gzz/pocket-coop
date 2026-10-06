local Constants = require("src.util.constants")

-- The play area and the two UI bands above/below it (CONTEXT.md, ADR-0009,
-- ADR-0017). The play area claims HEIGHT_FRACTION of the safe area's height;
-- the bands are whatever vertical space is left over around it.
local Layout = {}

local TILE_SIZE = Constants.TILE_SIZE

local HEIGHT_FRACTION = 0.85
local SIDE_MARGIN_FRACTION = 0.02

local function getSafeRect()
	local topInset, leftInset, bottomInset, rightInset = display.getSafeAreaInsets()
	return {
		minX = display.screenOriginX + leftInset,
		maxX = display.screenOriginX + display.actualContentWidth - rightInset,
		minY = display.screenOriginY + topInset,
		maxY = display.screenOriginY + display.actualContentHeight - bottomInset,
	}
end

-- Leftover height is split a third to the top band, the rest to the bottom.
local function computeBands()
	local safeRect = getSafeRect()
	local safeWidth = safeRect.maxX - safeRect.minX
	local safeHeight = safeRect.maxY - safeRect.minY

	local playHeight = safeHeight * HEIGHT_FRACTION
	local sideMargin = safeWidth * SIDE_MARGIN_FRACTION
	local topBandHeight = math.floor((safeHeight - playHeight) / 3)

	local playMinY = safeRect.minY + topBandHeight
	local playMaxY = playMinY + playHeight

	return {
		playRect = {
			minX = safeRect.minX + sideMargin,
			maxX = safeRect.maxX - sideMargin,
			minY = playMinY,
			maxY = playMaxY,
		},
		topBandRect = { minX = safeRect.minX, maxX = safeRect.maxX, minY = safeRect.minY, maxY = playMinY },
		bottomBandRect = { minX = safeRect.minX, maxX = safeRect.maxX, minY = playMaxY, maxY = safeRect.maxY },
	}
end

-- Where world objects may move and be placed. The bottom stops half a tile
-- short of the bottom band.
function Layout.getPlayArea()
	local rect = computeBands().playRect
	return {
		minX = rect.minX,
		maxX = rect.maxX,
		minY = rect.minY,
		maxY = rect.maxY - TILE_SIZE / 2,
	}
end

function Layout.getTopBandRect()
	return computeBands().topBandRect
end

function Layout.getBottomBandRect()
	return computeBands().bottomBandRect
end

return Layout
