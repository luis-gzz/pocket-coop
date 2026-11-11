local Constants = require("src.util.constants")

-- Small hearts that float up and fade - the feedback for petting a chicken.
local Hearts = {}

local PATH = "assets/fauna/heart.png"
local SIZE = 11 * Constants.UI_PIXEL_SCALE -- 11x11 art, whole screen px (ADR-0020)
local RISE = 14 * Constants.PIXEL_SCALE
local RISE_TIME = 900 -- ms
local JITTER_X = 5 * Constants.PIXEL_SCALE
local BURST_STAGGER = 90 -- ms between a burst's hearts

local layer

-- Call once, after the world and before the UI, so hearts draw between them.
function Hearts.createLayer()
	layer = display.newGroup()
	return layer
end

function Hearts.spawn(x, y)
	local heart = display.newImageRect(layer, PATH, SIZE, SIZE)
	heart.x = x + (math.random() * 2 - 1) * JITTER_X
	heart.y = y
	transition.to(heart, {
		y = y - RISE,
		alpha = 0,
		time = RISE_TIME,
		transition = easing.outQuad,
		onComplete = function()
			heart:removeSelf()
		end,
	})
end

function Hearts.burst(x, y, count)
	for i = 1, count do
		timer.performWithDelay((i - 1) * BURST_STAGGER + 1, function()
			Hearts.spawn(x, y)
		end)
	end
end

return Hearts
