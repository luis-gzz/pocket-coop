local contentWidth = 384
local ratio = display.pixelHeight / display.pixelWidth

-- Not a real Solar2D application setting - just declared here (unlocal'd, so
-- it's a global) because config.lua is guaranteed to run before every other
-- file. Toggles src/debug_overlay.lua's corner button + time-scale popover.
DEBUG_MODE = false

application =
{
	content =
	{
		width = contentWidth,
		height = math.ceil(contentWidth * ratio),
		scale = "letterbox",
		fps = 60,
	},
}
