-- The single source of simulated time every chicken's Gauges advances
-- against, replacing each chicken computing its own frame delta
-- independently (CONTEXT.md's "Clock"). Also owns the debug-only time-scale
-- multiplier (absorbing the old time_scale.lua) since scaling dt is part of
-- the same "what does a second of sim time mean right now" concern.
local Clock = {}

Clock.PRESETS = { 1, 10, 60, 300 }

local timeScale = 1
local now = 0
local dt = 0

-- Caps how much simulated time a single advance() call can cover, regardless
-- of the debug time-scale multiplier. Without this, a frame hitch (or the
-- app losing/regaining focus) can produce one huge raw dt, which at a high
-- time-scale would blow through many poop/lay-clock intervals in a single
-- call. Clamping the raw dt keeps the time-scale dial's intended
-- fast-forwarding (raw dt x up to 300) working at normal frame rates while
-- bounding worst-case bursts. (Moved here from gauges.lua - this is a
-- time-consistency concern, not a gauge-specific one.)
local MAX_RAW_DT = 0.25 -- seconds

-- Called once per frame by garden.lua's own enterFrame loop. Clamps rawDt,
-- applies the time-scale multiplier, and accumulates the shared `now`.
function Clock.advance(rawDt)
	dt = math.min(rawDt, MAX_RAW_DT) * timeScale
	now = now + dt
end

-- This frame's already-scaled dt, valid until the next advance() call.
function Clock.getDt()
	return dt
end

-- Total elapsed sim-seconds since load.
function Clock.getNow()
	return now
end

function Clock.getTimeScale()
	return timeScale
end

function Clock.setTimeScale(value)
	timeScale = value
end

return Clock
