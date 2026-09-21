display.setStatusBar(display.HiddenStatusBar)

-- Keep the 16px pixel art crisp at the non-integer scale factors the
-- letterbox content scaling can produce across devices.
display.setDefault("minTextureFilter", "nearest")
display.setDefault("magTextureFilter", "nearest")

-- Backdrop behind the island, filling the whole camera.
display.setDefault("background", 0xA2 / 0xFF, 0xDC / 0xFF, 0xC7 / 0xFF)

local Island = require("src.systems.island")
local YSort = require("src.systems.y_sort")
local Garden = require("src.systems.garden")
local Hud = require("src.ui.hud")
local Toolbar = require("src.ui.toolbar")
local Save = require("src.systems.save")
local DebugOverlay = require("src.ui.debug_overlay")

local AUTOSAVE_INTERVAL = 20 * 1000 -- ms

Island.create()

-- The floor layer (hen beds) - created first so it's inserted, and therefore
-- always renders, behind the main world group below (ADR-0014).
YSort.createFloorLayer()

-- World objects (chicken, droppings, eggs, food) depth-sort against each
-- other in this group (ADR-0005). Hen beds don't join it - see the floor
-- layer above.
YSort.createGroup()

-- The save file is { garden = ..., feed = ... } (ADR-0007, ADR-0011).
-- Garden owns loading itself, its chickens, and Feed together, and wires
-- its own save callbacks - main.lua only needs to trigger a save on a timer
-- and on suspend/exit.
local saved = Save.load()
Garden.load(saved)

Hud.create()
Toolbar.create()

if DEBUG_MODE then
	DebugOverlay.create()
end

timer.performWithDelay(AUTOSAVE_INTERVAL, Garden.save, 0)

Runtime:addEventListener("system", function(event)
	if event.type == "applicationExit" or event.type == "applicationSuspend" then
		Garden.save()
	end
end)
