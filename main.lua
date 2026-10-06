display.setStatusBar(display.HiddenStatusBar)

-- Keep the 16px pixel art crisp at the non-integer scale factors the
-- letterbox content scaling can produce across devices.
display.setDefault("minTextureFilter", "nearest")
display.setDefault("magTextureFilter", "nearest")

-- At those same non-integer scales the GPU can land a sample just past a
-- frame's edge, and with nearest filtering that pulls in a whole texel from
-- the neighboring frame in the sheet - showing up as thin dark lines along
-- tile/sprite edges. This insets every image sheet frame's sampling by half a
-- texel. Must be set before any graphics.newImageSheet call.
display.setDefault("isImageSheetSampledInsideFrame", true)

local Ground = require("src.systems.ground")
local YSort = require("src.systems.y_sort")
local Garden = require("src.systems.garden")
local Hud = require("src.ui.hud")
local Toolbar = require("src.ui.toolbar")
local Save = require("src.systems.save")
local DebugOverlay = require("src.ui.debug_overlay")
local WelcomeCard = require("src.ui.welcome_card")

local AUTOSAVE_INTERVAL = 20 * 1000 -- ms

Ground.create()

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

-- Catches up for time away and shows the welcome-back card after a full
-- pass. Runs after the UI exists so the card can show on launch.
local function returnToNow()
	local didFullPass, elapsed = Garden.returnToNow()
	if didFullPass then
		WelcomeCard.show(elapsed)
	end
end
returnToNow()

timer.performWithDelay(AUTOSAVE_INTERVAL, Garden.save, 0)

-- Saving on the way out stamps the save's lastUpdate; coming back returns
-- the garden to now.
Runtime:addEventListener("system", function(event)
	if event.type == "applicationExit" or event.type == "applicationSuspend" then
		Garden.save()
	elseif event.type == "applicationResume" then
		returnToNow()
	end
end)
