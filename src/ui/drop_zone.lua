local Layout = require("src.ui.layout")

-- The toolbar band as a drop target for a fixture dragged off the map
-- (CONTEXT.md's Fixture). Requires nothing but Layout, so fixture views
-- can report hovering, and Garden a landing, without a require loop.
local DropZone = {}

local hovering = false
local hoverListeners = {}
local landListeners = {}

-- Whether a content point is over the toolbar band.
function DropZone.contains(x, y)
	local band = Layout.getBottomBandRect()
	return y >= band.minY and x >= band.minX and x <= band.maxX
end

function DropZone.setHover(isHovering)
	if hovering == isHovering then
		return
	end
	hovering = isHovering
	for _, listener in ipairs(hoverListeners) do
		listener(hovering)
	end
end

-- listener(isHovering)
function DropZone.onHover(listener)
	table.insert(hoverListeners, listener)
end

-- area is "toolbar" or "barn"; index is the slot it ended up in.
function DropZone.landed(area, index)
	for _, listener in ipairs(landListeners) do
		listener(area, index)
	end
end

-- listener(area, index)
function DropZone.onLanded(listener)
	table.insert(landListeners, listener)
end

return DropZone
