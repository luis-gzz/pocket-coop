local Constants = require("src.util.constants")

-- Pixel-art 9-slice frames behind every slot, panel, and button (ADR-0024):
-- a 5x5 sprite cut into 2px corners and 1px edges/center, drawn at world scale.
local Frame = {}

local CORNER = 2 -- art px
local STYLES = {
	frame = "assets/ui/frame.png",
	selected = "assets/ui/frame_selected.png",
	button = "assets/ui/frame_button.png",
	backing = "assets/ui/frame_backing.png",
}

local sheets = {}

local function getSheet(style)
	if not sheets[style] then
		local frames = {}
		for _, y in ipairs({ { 0, CORNER }, { CORNER, 1 }, { CORNER + 1, CORNER } }) do
			for _, x in ipairs({ { 0, CORNER }, { CORNER, 1 }, { CORNER + 1, CORNER } }) do
				table.insert(frames, { x = x[1], y = y[1], width = x[2], height = y[2] })
			end
		end
		-- Inset sampling keeps stretched 1px edges from bleeding into their neighbours.
		display.setDefault("isImageSheetSampledInsideFrame", true)
		sheets[style] = graphics.newImageSheet(STYLES[style], { frames = frames })
		display.setDefault("isImageSheetSampledInsideFrame", false)
	end
	return sheets[style]
end

-- Rounds a content length to a whole number of art pixels (world-sized by default).
function Frame.snap(length, pixel)
	pixel = pixel or Constants.PIXEL_SCALE
	return math.max(1, math.floor(length / pixel + 0.5)) * pixel
end

-- A frame with its top-left at (x, y); returns it and its snapped size.
-- style: a STYLES key, "frame" by default; pixel: art px size, world by default.
function Frame.new(parent, x, y, width, height, style, pixel)
	pixel = pixel or Constants.PIXEL_SCALE
	width, height = Frame.snap(width, pixel), Frame.snap(height, pixel)
	local corner = CORNER * pixel
	local sheet = getSheet(style or "frame")
	local group = display.newGroup()
	parent:insert(group)
	group.x, group.y = x, y

	local columns = { { 0, corner }, { corner, width - corner * 2 }, { width - corner, corner } }
	local rows = { { 0, corner }, { corner, height - corner * 2 }, { height - corner, corner } }
	local index = 0
	for _, row in ipairs(rows) do
		for _, column in ipairs(columns) do
			index = index + 1
			if column[2] > 0 and row[2] > 0 then
				local piece = display.newImageRect(group, sheet, index, column[2], row[2])
				piece.anchorX, piece.anchorY = 0, 0
				piece.x, piece.y = column[1], row[1]
			end
		end
	end
	return group, width, height
end

return Frame
