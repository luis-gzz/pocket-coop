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
local Feed = require("src.feed")
local Hud = require("src.hud")
local Toolbar = require("src.toolbar")
local Save = require("src.save")
local DebugOverlay = require("src.debug_overlay")

local AUTOSAVE_INTERVAL = 20 * 1000 -- ms

Island.create()

-- World objects (chicken, droppings, hen beds, eggs, food) depth-sort
-- against each other in this group (ADR-0005).
YSort.createGroup()

-- The save file is {chicken = ..., world = ..., feed = ...} (ADR-0007,
-- ADR-0011). Feed loads before Chicken so it's visible on the first decide.
local saved = Save.load()
Coop.load(saved and saved.world)
Feed.load(saved and saved.feed)
local chicken = Chicken.new(saved and saved.chicken)

Hud.create()
Toolbar.create()

if DEBUG_MODE then
	DebugOverlay.create()
end

local function saveNow()
	Save.write({ chicken = chicken:getSaveData(), world = Coop.getSaveData(), feed = Feed.getSaveData() })
end

-- Coop and Feed each save immediately on their own discrete events, not
-- just the periodic/suspend saves below.
Coop.setSaveCallback(saveNow)
Feed.setSaveCallback(saveNow)

timer.performWithDelay(AUTOSAVE_INTERVAL, saveNow, 0)

Runtime:addEventListener("system", function(event)
	if event.type == "applicationExit" or event.type == "applicationSuspend" then
		saveNow()
	end
end)
