local Constants = require("src.constants")

-- The island and the two UI bands above/below it (CONTEXT.md, ADR-0009).
-- The island is generated first, sized to fill WIDTH_FRACTION/HEIGHT_FRACTION
-- of the safe area (floored to whole tiles); the bands are whatever
-- vertical space is left over around it, not a fixed size of their own.
local Layout = {}

local TILE_SIZE = Constants.TILE_SIZE

local WIDTH_FRACTION = 1.0
local HEIGHT_FRACTION = 0.85

local function getSafeRect()
	local topInset, leftInset, bottomInset, rightInset = display.getSafeAreaInsets()
	return {
		minX = display.screenOriginX + leftInset,
		maxX = display.screenOriginX + display.actualContentWidth - rightInset,
		minY = display.screenOriginY + topInset,
		maxY = display.screenOriginY + display.actualContentHeight - bottomInset,
	}
end

-- Fits a whole number of tiles into WIDTH_FRACTION/HEIGHT_FRACTION of the
-- safe area (so the island's border tiles are never cut off mid-tile),
-- horizontally centered. Whatever vertical space the island doesn't claim
-- is split between the top and bottom bands - evenly for now, with the
-- bottom band taking the extra pixel when it doesn't split evenly
-- (ADR-0009).
local function computeBands()
	local safeRect = getSafeRect()
	local safeWidth = safeRect.maxX - safeRect.minX
	local safeHeight = safeRect.maxY - safeRect.minY

	local columns = math.max(1, math.floor((safeWidth * WIDTH_FRACTION) / TILE_SIZE))
	local rows = math.max(1, math.floor((safeHeight * HEIGHT_FRACTION) / TILE_SIZE))

	local islandWidth = columns * TILE_SIZE
	local islandHeight = rows * TILE_SIZE
	local islandMinX = safeRect.minX + (safeWidth - islandWidth) / 2

	local leftover = safeHeight - islandHeight
	local topBandHeight = math.floor(leftover / 3)

	local islandMinY = safeRect.minY + topBandHeight
	local islandMaxY = islandMinY + islandHeight

	return {
		columns = columns,
		rows = rows,
		islandRect = { minX = islandMinX, maxX = islandMinX + islandWidth, minY = islandMinY, maxY = islandMaxY },
		topBandRect = { minX = safeRect.minX, maxX = safeRect.maxX, minY = safeRect.minY, maxY = islandMinY },
		bottomBandRect = { minX = safeRect.minX, maxX = safeRect.maxX, minY = islandMaxY, maxY = safeRect.maxY },
	}
end

-- The island's rect plus its tile grid dimensions - src/island.lua renders
-- into this instead of computing its own size (ADR-0009).
function Layout.getIslandRect()
	local bands = computeBands()
	return { rect = bands.islandRect, columns = bands.columns, rows = bands.rows }
end

function Layout.getTopBandRect()
	return computeBands().topBandRect
end

function Layout.getBottomBandRect()
	return computeBands().bottomBandRect
end

return Layout
