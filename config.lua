local contentWidth = 384
local ratio = display.pixelHeight / display.pixelWidth

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
