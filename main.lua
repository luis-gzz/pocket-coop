display.setStatusBar(display.HiddenStatusBar)

-- Keep the 16px pixel art crisp at the non-integer scale factors the
-- letterbox content scaling can produce across devices.
display.setDefault("minTextureFilter", "nearest")
display.setDefault("magTextureFilter", "nearest")

-- Backdrop behind the island, filling the whole camera.
display.setDefault("background", 0xA2 / 0xFF, 0xDC / 0xFF, 0xC7 / 0xFF)

local Island = require("src.island")
local YSort = require("src.y_sort")
local Chicken = require("src.chicken")
local Save = require("src.save")
local DebugOverlay = require("src.debug_overlay")

local AUTOSAVE_INTERVAL = 20 * 1000 -- ms

Island.create()

-- World objects (chicken, droppings) live in this group and depth-sort
-- against each other (ADR-0005). Created after the background and before
-- any world object, so the group sits above the island and below whatever's
-- created after it (the debug overlay, and the tooltip when it opens).
YSort.createGroup()

local chicken = Chicken.new(Save.load())
if DEBUG_MODE then
	DebugOverlay.create()
end

local function saveNow()
	Save.write(chicken:getSaveData())
end

timer.performWithDelay(AUTOSAVE_INTERVAL, saveNow, 0)

Runtime:addEventListener("system", function(event)
	if event.type == "applicationExit" or event.type == "applicationSuspend" then
		saveNow()
	end
end)
