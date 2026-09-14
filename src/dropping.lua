local Constants = require("src.constants")
local YSort = require("src.y_sort")

-- The visual, tappable side of a Gauges dropping record - Gauges owns the
-- data, this owns the display object and turns a tap into a cleanup.
local Dropping = {}
Dropping.__index = Dropping

local IMAGE_PATH = "assets/fauna/dung.png"
local NATIVE_WIDTH, NATIVE_HEIGHT = 8, 6
local WIDTH = NATIVE_WIDTH * Constants.PIXEL_SCALE
local HEIGHT = NATIVE_HEIGHT * Constants.PIXEL_SCALE

-- record: the {x, y, createdAt} table from Gauges. onClean(dropping) is
-- called when tapped, so the caller can remove it from Gauges and from
-- whatever list is tracking active droppings.
function Dropping.new(record, onClean)
	local self = setmetatable({}, Dropping)
	self.record = record

	self.image = display.newImageRect(IMAGE_PATH, WIDTH, HEIGHT)
	YSort.getGroup():insert(self.image)
	self.image.x = record.x
	self.image.y = record.y
	self.image:addEventListener("tap", function()
		onClean(self)
		return true
	end)
	-- image.y is the dropping's vertical center (default anchor); depth
	-- sorts by bottom edge like every world object (ADR-0006), so add half
	-- its height.
	YSort.add(self.image, function(image)
		return image.y + HEIGHT / 2
	end)

	return self
end

function Dropping:destroy()
	if self.image then
		YSort.remove(self.image)
		self.image:removeSelf()
		self.image = nil
	end
end

return Dropping
