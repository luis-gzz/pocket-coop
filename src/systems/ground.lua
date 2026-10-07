local Constants = require("src.util.constants")

-- Plain grass tiled across the whole camera (CONTEXT.md, ADR-0017). Purely
-- visual - the play area's bounds live in Layout.
local Ground = {}

local SHEET_PATH = "assets/GrassTileset/GrassHills.png"
local SHEET_COLUMNS, SHEET_ROWS = 10, 6
local SHEET_TILE_SIZE = 16

-- GrassHills.png's interior (borderless) grass variants.
local GRASS_FRAMES = { 27, 50, 59, 60 }

local sheet = graphics.newImageSheet(SHEET_PATH, {
	width = SHEET_TILE_SIZE,
	height = SHEET_TILE_SIZE,
	numFrames = SHEET_COLUMNS * SHEET_ROWS,
	sheetContentWidth = SHEET_COLUMNS * SHEET_TILE_SIZE,
	sheetContentHeight = SHEET_ROWS * SHEET_TILE_SIZE,
})

local TILE_SIZE = Constants.TILE_SIZE

-- Anchored at the camera's top-left; tiles past the right/bottom edge are
-- simply cut off.
function Ground.create()
	local group = display.newGroup()
	local originX, originY = display.screenOriginX, display.screenOriginY
	local columns = math.ceil(display.actualContentWidth / TILE_SIZE)
	local rows = math.ceil(display.actualContentHeight / TILE_SIZE)

	for row = 0, rows - 1 do
		for column = 0, columns - 1 do
			local frame = GRASS_FRAMES[math.random(#GRASS_FRAMES)]
			local tile = display.newImageRect(group, sheet, frame, TILE_SIZE, TILE_SIZE)
			tile.x = originX + column * TILE_SIZE + TILE_SIZE / 2
			tile.y = originY + row * TILE_SIZE + TILE_SIZE / 2
		end
	end

	return group
end

return Ground
