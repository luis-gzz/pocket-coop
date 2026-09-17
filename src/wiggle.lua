-- Shared "this is being picked up" wiggle: rotates a target back and forth
-- by +/-angle every stepTime ms for as long as isActive() returns true, then
-- eases back to a neutral rotation once stopped. Callers own their own
-- angle/timing and touch-handling - only the animation shape lives here.
local Wiggle = {}

-- isActive is polled at the start of every step, so the wiggle halts itself
-- the moment the caller's own state goes false, without Wiggle needing to
-- know why (a chicken's self.isHeld, a bed's isDragging, a ghost's ~= nil).
function Wiggle.start(target, angle, stepTime, isActive)
	local handle = { target = target, stepTime = stepTime, transitionHandle = nil }
	local nextAngle = angle

	local function step()
		if not isActive() then
			return
		end
		handle.transitionHandle = transition.to(target, {
			rotation = nextAngle,
			time = stepTime,
			onComplete = step,
		})
		nextAngle = -nextAngle
	end
	step()

	return handle
end

function Wiggle.stop(handle)
	if not handle then
		return
	end
	if handle.transitionHandle then
		transition.cancel(handle.transitionHandle)
	end
	transition.to(handle.target, { rotation = 0, time = handle.stepTime })
end

return Wiggle
