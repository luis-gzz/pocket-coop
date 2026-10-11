local Gauges = require("src.objects.chicken.gauges")

-- Tooltip icons (src/ui/tooltip.lua row.icon) drawn from the happy/meh/sad
-- face sheet.
local HappinessIcon = {}

local SHEET_PATH = "assets/objects/happy_icon.png"
local FRAME_SIZE = 16
local FRAMES = { happy = 1, meh = 2, sad = 3 }
local FRAME_COUNT = 3

local sheet = graphics.newImageSheet(SHEET_PATH, {
	width = FRAME_SIZE,
	height = FRAME_SIZE,
	numFrames = FRAME_COUNT,
	sheetContentWidth = FRAME_SIZE * FRAME_COUNT,
	sheetContentHeight = FRAME_SIZE,
})

HappinessIcon.HAPPY = { sheet = sheet, frameCount = FRAME_COUNT, frame = FRAMES.happy }

-- A face that follows getHappiness() live.
function HappinessIcon.live(getHappiness)
	return {
		sheet = sheet,
		frameCount = FRAME_COUNT,
		getFrame = function()
			return FRAMES[Gauges.happinessFace(getHappiness())]
		end,
	}
end

return HappinessIcon
