-- The single source of simulated time every chicken's Gauges advances
-- against, replacing each chicken computing its own frame delta
-- independently (CONTEXT.md's "Clock"). Also owns the debug-only time-scale
-- multiplier (absorbing the old time_scale.lua) since scaling dt is part of
-- the same "what does a second of sim time mean right now" concern - and,
-- for the same reason, sim-time timers (Clock.after), so every timer that
-- affects the gauges speeds up along with them (ADR-0015).
local Clock = {}

Clock.PRESETS = { 1, 10, 60, 300 }

local timeScale = 1
local now = 0
local dt = 0

-- Pending sim-time timers: { fireAt, fn, cancelled }.
local timers = {}

-- Caps how much simulated time a single advance() call can cover, regardless
-- of the debug time-scale multiplier. Without this, a frame hitch (or the
-- app losing/regaining focus) can produce one huge raw dt, which at a high
-- time-scale would blow through many poop/lay intervals in a single
-- call. Clamping the raw dt keeps the time-scale dial's intended
-- fast-forwarding (raw dt x up to 300) working at normal frame rates while
-- bounding worst-case bursts. Time spent suspended is covered by offline
-- catch-up instead (ADR-0016).
local MAX_RAW_DT = 0.25 -- seconds

-- Called once per frame by garden.lua's own enterFrame loop. Clamps rawDt,
-- applies the time-scale multiplier, accumulates the shared `now`, and fires
-- any sim-time timers that came due.
function Clock.advance(rawDt)
	dt = math.min(rawDt, MAX_RAW_DT) * timeScale
	now = now + dt

	-- Swapped out first so a callback scheduling a new timer lands in the
	-- next frame's list rather than mutating this one mid-iteration.
	local due = timers
	timers = {}
	for _, handle in ipairs(due) do
		if not handle.cancelled then
			if now >= handle.fireAt then
				handle.cancelled = true
				handle.fn()
			else
				table.insert(timers, handle)
			end
		end
	end
end

-- Runs fn once, after `seconds` of sim time. Returns a handle for
-- Clock.cancel.
function Clock.after(seconds, fn)
	local handle = { fireAt = now + seconds, fn = fn, cancelled = false }
	table.insert(timers, handle)
	return handle
end

function Clock.cancel(handle)
	if handle then
		handle.cancelled = true
	end
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
