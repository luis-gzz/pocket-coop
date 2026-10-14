local Constants = require("src.util.constants")

-- The bucket (CONTEXT.md): a tool, never a world object. Dropped on a
-- water bowl, Bowls fills it to full.
local Bucket = {}

local IMAGE_PATH = "assets/objects/bucket.png"
local NATIVE_WIDTH, NATIVE_HEIGHT = 11, 12

Bucket.DESCRIPTOR = {
	icon = IMAGE_PATH,
	width = NATIVE_WIDTH * Constants.PIXEL_SCALE,
	height = NATIVE_HEIGHT * Constants.PIXEL_SCALE,
	type = "bucket",
}

return Bucket
