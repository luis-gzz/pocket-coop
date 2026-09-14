-- Debug-only multiplier applied to every gauge's rate x delta-time update,
-- so testers can compress real time instead of waiting it out live.
local TimeScale = {}

local current = 1

TimeScale.PRESETS = { 1, 10, 60, 300 }

function TimeScale.get()
	return current
end

function TimeScale.set(value)
	current = value
end

return TimeScale
