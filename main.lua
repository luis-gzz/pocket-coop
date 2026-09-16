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
local Coop = require("src.coop")
local Hud = require("src.hud")
local Toolbar = require("src.toolbar")
local Save = require("src.save")
local DebugOverlay = require("src.debug_overlay")

local AUTOSAVE_INTERVAL = 20 * 1000 -- ms

Island.create()

-- World objects (chicken, droppings, hen beds, eggs) live in this group and
-- depth-sort against each other (ADR-0005). Created after the background
-- and before any world object, so the group sits above the island and below
-- whatever's created after it (the UI bands, the debug overlay, and the
-- tooltip when it opens).
YSort.createGroup()

-- The save file is {chicken = ..., world = ...} - the chicken's own gauge
-- data alongside Coop's shared beds/eggs/collected-count (ADR-0007).
local saved = Save.load()
Coop.load(saved and saved.world)
local chicken = Chicken.new(saved and saved.chicken)

Hud.create()
Toolbar.create()

if DEBUG_MODE then
	DebugOverlay.create()
end

local function saveNow()
	Save.write({ chicken = chicken:getSaveData(), world = Coop.getSaveData() })
end

-- Coop saves immediately on a lay, a collect, or a placement (not just the
-- periodic/suspend saves below), so a kill between a lay and a collect can't
-- lose the egg or rewind the refractory clock.
Coop.setSaveCallback(saveNow)

timer.performWithDelay(AUTOSAVE_INTERVAL, saveNow, 0)

Runtime:addEventListener("system", function(event)
	if event.type == "applicationExit" or event.type == "applicationSuspend" then
		saveNow()
	end
end)
