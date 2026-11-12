display.setStatusBar(display.HiddenStatusBar)

-- Solar2D doesn't seed math.random, so every launch replayed the same picks.
math.randomseed(os.time())

-- Keep the 16px pixel art crisp at the non-integer scale factors the
-- letterbox content scaling can produce across devices.
display.setDefault("minTextureFilter", "nearest")
display.setDefault("magTextureFilter", "nearest")

-- Art scales are whole screen pixels (ADR-0020), so frames line up exactly;
-- the half-texel inset would only squish each frame's edge pixels.
display.setDefault("isImageSheetSampledInsideFrame", false)

local Ground = require("src.systems.ground")
local YSort = require("src.systems.y_sort")
local Garden = require("src.systems.garden")
local Hud = require("src.ui.hud")
local Toolbar = require("src.ui.toolbar")
local Selection = require("src.ui.selection")
local Hearts = require("src.objects.hearts")
local Save = require("src.systems.save")
local DebugOverlay = require("src.ui.debug_overlay")
local WelcomeCard = require("src.ui.welcome_card")

local AUTOSAVE_INTERVAL = 20 * 1000 -- ms

Ground.create()

-- The floor layer (flat objects like ash) - created first so it's inserted,
-- and therefore always renders, behind the main world group below (ADR-0014).
YSort.createFloorLayer()

-- World objects (chicken, droppings, eggs, food) depth-sort against each
-- other in this group (ADR-0005), fixtures by their sort line (ADR-0021).
YSort.createGroup()

-- The save file is { garden = ..., feed = ... } (ADR-0007, ADR-0011).
-- Garden owns loading itself, its chickens, and Feed together, and wires
-- its own save callbacks - main.lua only needs to trigger a save on a timer
-- and on suspend/exit.
local saved = Save.load()
Garden.load(saved)

-- Above the world, below the UI: a tap uses the selected item, and a
-- selection lasts one successful use; a miss keeps it (ADR-0022).
Selection.createCatcher(function(itemType, x, y)
	if Garden.tryPlace(itemType, x, y) then
		Selection.clear()
	end
end)

Hearts.createLayer()

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
	else
		Garden.startHeldEggs()
	end
end
-- A held egg is laid a little after the welcome-back card closes (ADR-0029).
WelcomeCard.onHidden(Garden.startHeldEggs)
returnToNow()

timer.performWithDelay(AUTOSAVE_INTERVAL, Garden.save, 0)

-- Saving on the way out stamps the save's lastUpdate; coming back returns
-- the garden to now.
Runtime:addEventListener("system", function(event)
	if event.type == "applicationExit" or event.type == "applicationSuspend" then
		Selection.clear()
		Garden.landHeldEggs()
		Garden.save()
	elseif event.type == "applicationResume" then
		returnToNow()
	end
end)
