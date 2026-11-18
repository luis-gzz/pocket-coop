local Constants = require("src.util.constants")

-- Debug-only hand that marks where the player is touching, for recording
-- videos. Off by default; toggled from the debug overlay.
local Cursor = {}

local IMAGE = "assets/ui/Cursor_02.png"
local NATIVE_SIZE = 64
-- Fingertip within the 64x64 art, in art pixels: sits on the touch point.
local TIP_X, TIP_Y = 25, 18

-- One whole step below the UI pixel scale, so it stays crisp (ADR-0020).
local PPA = math.max(1, Constants.UI_PPA - 1)
local SCALE = PPA / Constants.DEVICE_SCALE

local LINGER_MS = 1500
local FADE_MS = 300

Cursor.enabled = false

local hand, catcher
local lingerTimer, fadeTransition
local focused -- object holding touch focus, while we listen to it

local function snap(value)
	return math.floor(value * Constants.DEVICE_SCALE + 0.5) / Constants.DEVICE_SCALE
end

local function cancelHide()
	if lingerTimer then
		timer.cancel(lingerTimer)
		lingerTimer = nil
	end
	if fadeTransition then
		transition.cancel(fadeTransition)
		fadeTransition = nil
	end
end

local function showAt(x, y)
	cancelHide()
	hand.x, hand.y = snap(x), snap(y)
	hand.alpha = 1
	hand.isVisible = true
end

local function release()
	cancelHide()
	if not hand.isVisible then
		return
	end
	lingerTimer = timer.performWithDelay(LINGER_MS, function()
		lingerTimer = nil
		fadeTransition = transition.to(hand, {
			alpha = 0,
			time = FADE_MS,
			onComplete = function()
				fadeTransition = nil
				hand.isVisible = false
			end,
		})
	end)
end

local function onTouch(event)
	if not Cursor.enabled then
		return false
	end
	if event.phase == "ended" or event.phase == "cancelled" then
		hand.x, hand.y = snap(event.x), snap(event.y)
		release()
	else
		showAt(event.x, event.y)
	end
	return false
end

local function stopFollowingFocus()
	if focused then
		if focused.removeEventListener then
			focused:removeEventListener("touch", onTouch)
		end
		focused = nil
	end
end

-- Drags take touch focus, so later phases skip the catcher; follow the
-- focused object's own touch events instead.
local function wrapSetFocus()
	local stage = display.getCurrentStage()
	local setFocus = stage.setFocus
	stage.setFocus = function(self, object, id)
		stopFollowingFocus()
		if object then
			focused = object
			object:addEventListener("touch", onTouch)
		elseif Cursor.enabled then
			-- Focus usually clears on release; a moved event re-shows the hand.
			release()
		end
		return setFocus(self, object, id)
	end
end

-- Keeps the catcher and hand above UI created after them (popovers, cards).
local function keepOnTop()
	if not Cursor.enabled then
		return
	end
	catcher:toFront()
	hand:toFront()
end

function Cursor.create()
	catcher = display.newRect(
		display.screenOriginX + display.actualContentWidth / 2,
		display.screenOriginY + display.actualContentHeight / 2,
		display.actualContentWidth,
		display.actualContentHeight
	)
	catcher.isVisible = false
	catcher.isHitTestable = Cursor.enabled
	catcher:addEventListener("touch", onTouch)

	local size = NATIVE_SIZE * SCALE
	hand = display.newImageRect(IMAGE, size, size)
	hand.anchorX = TIP_X / NATIVE_SIZE
	hand.anchorY = TIP_Y / NATIVE_SIZE
	hand.isVisible = false

	wrapSetFocus()
	Runtime:addEventListener("enterFrame", keepOnTop)
end

function Cursor.setEnabled(enabled)
	Cursor.enabled = enabled
	catcher.isHitTestable = enabled
	if not enabled then
		cancelHide()
		hand.isVisible = false
	end
end

return Cursor
