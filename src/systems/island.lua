local Constants = require("src.util.constants")
local Layout = require("src.ui.layout")
local CORNER_FRAMES = require("src.systems.grass_autotile_frames")

local Island = {}

local SHEET_PATH = "assets/GrassTileset/GrassHills.png"
local SHEET_COLUMNS, SHEET_ROWS = 10, 6
local SHEET_TILE_SIZE = 16

local sheet = graphics.newImageSheet(SHEET_PATH, {
	width = SHEET_TILE_SIZE,
	height = SHEET_TILE_SIZE,
	numFrames = SHEET_COLUMNS * SHEET_ROWS,
	sheetContentWidth = SHEET_COLUMNS * SHEET_TILE_SIZE,
	sheetContentHeight = SHEET_ROWS * SHEET_TILE_SIZE,
})

local TILE_SIZE = Constants.TILE_SIZE
local FALLBACK_KEY = "FULL|FULL|FULL|FULL"

-- Each tile is rendered slightly larger than TILE_SIZE (same center, so it
-- overlaps its neighbors by half this on every edge) to hide the hairline
-- seams that otherwise show up between adjacent tiles on a real device: every
-- tile is its own display object, so the GPU rounds each one's edges to the
-- nearest physical pixel independently, and TILE_SIZE being a non-integer
-- device-dependent value (PIXEL_SCALE isn't always a whole number) means
-- neighboring edges can round to different pixels, leaving a thin gap of
-- Backdrop color between them. Imperceptible here since it's the same
-- seamless grass texture with nearest-neighbor filtering overlapping itself.
-- 1 wasn't quite enough on a real device, then 2 still left a few gaps in a
-- repeated pattern (possibly not pure rounding noise - worth a closer look
-- if 4 doesn't fully clear it).
local TILE_RENDER_OVERLAP = 4

-- Every island tile is grass for now; a position outside the grid counts as
-- a different terrain, which is exactly what gives the island a bordered
-- edge instead of looking like an infinite flat field.
local function sameType(col, row, columns, rows)
	return col >= 0 and col < columns and row >= 0 and row < rows
end

local function cornerState(edgeA, edgeB, diagonal)
	if not edgeA or not edgeB then
		return "OPEN"
	elseif not diagonal then
		return "CONCAVE"
	end
	return "FULL"
end

local function pickFrame(col, row, columns, rows)
	local n = sameType(col, row - 1, columns, rows)
	local s = sameType(col, row + 1, columns, rows)
	local w = sameType(col - 1, row, columns, rows)
	local e = sameType(col + 1, row, columns, rows)
	local nw = sameType(col - 1, row - 1, columns, rows)
	local ne = sameType(col + 1, row - 1, columns, rows)
	local sw = sameType(col - 1, row + 1, columns, rows)
	local se = sameType(col + 1, row + 1, columns, rows)

	local key = table.concat({
		cornerState(n, w, nw),
		cornerState(n, e, ne),
		cornerState(s, w, sw),
		cornerState(s, e, se),
	}, "|")

	local frames = CORNER_FRAMES[key] or CORNER_FRAMES[FALLBACK_KEY]
	return frames[math.random(#frames)]
end

-- The rectangle the chicken is allowed to move within: the full island
-- rectangle, except the bottom edge is pulled in by half a tile.
function Island.getInnerBounds()
	local layout = Layout.getIslandRect()
	local rect = layout.rect
	return {
		minX = rect.minX,
		maxX = rect.maxX,
		minY = rect.minY,
		maxY = rect.maxY - TILE_SIZE / 2,
	}
end

-- Tiles the rect Layout.getIslandRect() hands back with the grass autotile
-- set. Each tile's art is picked from GrassHills.png based on which of its 8
-- neighbors fall outside the island grid, using the corner bitmask decoded
-- from assets/GrassTileset/Autotile_BitmaskRef1.png.
function Island.create()
	local group = display.newGroup()
	local layout = Layout.getIslandRect()
	local rect = layout.rect

	for row = 0, layout.rows - 1 do
		for column = 0, layout.columns - 1 do
			local x = rect.minX + column * TILE_SIZE + TILE_SIZE / 2
			local y = rect.minY + row * TILE_SIZE + TILE_SIZE / 2
			local frame = pickFrame(column, row, layout.columns, layout.rows)
			local tile = display.newImageRect(
				group, sheet, frame, TILE_SIZE + TILE_RENDER_OVERLAP, TILE_SIZE + TILE_RENDER_OVERLAP
			)
			tile.x = x
			tile.y = y
		end
	end

	return group
end

return Island
