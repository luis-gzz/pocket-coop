local Layout = require("src.ui.layout")

-- The selected toolbar item (CONTEXT.md's Selected (item)): while one is
-- selected, a tap anywhere in the play area uses it instead of reaching
-- what's beneath (ADR-0022). Requires nothing but Layout, so any module can
-- read it without a require loop.
local Selection = {}

local selectedType = nil
local listeners = {}
local catcher = nil

function Selection.get()
	return selectedType
end

local function notify()
	if catcher then
		catcher.isHitTestable = selectedType ~= nil
	end
	for _, listener in ipairs(listeners) do
		listener(selectedType)
	end
end

function Selection.set(itemType)
	if selectedType == itemType then
		return
	end
	selectedType = itemType
	notify()
end

function Selection.clear()
	Selection.set(nil)
end

-- listener(itemType or nil), called after every change.
function Selection.onChanged(listener)
	table.insert(listeners, listener)
end

-- The play-area tap catcher. Create it above the world and below the UI.
-- It listens for "tap" only, so long-press drags still reach world objects
-- (Solar2D hit-tests touch and tap separately). onUse(itemType, x, y).
function Selection.createCatcher(onUse)
	local bounds = Layout.getPlayArea()
	catcher = display.newRect(
		(bounds.minX + bounds.maxX) / 2, (bounds.minY + bounds.maxY) / 2,
		bounds.maxX - bounds.minX, bounds.maxY - bounds.minY
	)
	catcher.isVisible = false
	catcher.isHitTestable = false
	catcher:addEventListener("tap", function(event)
		if selectedType then
			onUse(selectedType, event.x, event.y)
		end
		return true
	end)
end

return Selection
