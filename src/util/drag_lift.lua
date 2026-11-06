-- Lifts a dragged object so its bottom edge sits GAP above the fingertip,
-- easing up when the drag starts; its sideways grab offset is kept.
local DragLift = {}

local GAP = 20 -- content pt between the touch point and the object's bottom edge
local EASE_TIME = 100 -- ms

-- bottomOffset: how far the object's bottom edge sits below its (x, y).
-- apply(x, y) places the object; it's called on every move and while easing.
function DragLift.begin(x, y, fingerX, fingerY, bottomOffset, apply)
	local lift = { offsetX = x - fingerX, offsetY = y - fingerY, fingerX = fingerX, fingerY = fingerY, apply = apply }
	local function update()
		lift.apply(lift.fingerX + lift.offsetX, lift.fingerY + lift.offsetY)
	end
	lift.update = update
	Runtime:addEventListener("enterFrame", update)
	lift.tween = transition.to(lift, {
		offsetY = -(GAP + bottomOffset),
		time = EASE_TIME,
		transition = easing.outQuad,
		onComplete = function()
			Runtime:removeEventListener("enterFrame", update)
		end,
	})
	return lift
end

function DragLift.move(lift, fingerX, fingerY)
	lift.fingerX, lift.fingerY = fingerX, fingerY
	lift.update()
end

-- Stops easing; the object stays where it was last placed.
function DragLift.finish(lift)
	if lift then
		transition.cancel(lift.tween)
		Runtime:removeEventListener("enterFrame", lift.update)
	end
end

return DragLift
