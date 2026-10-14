-- Plans a chicken's wander route: a random walk of waypoints run through a
-- Catmull-Rom spline, sampled into a polyline the chicken follows by distance.
local WanderRoute = {}

local WAYPOINTS = { min = 3, max = 5 }
local LEG = { min = 25, max = 45 } -- points between waypoints
local MAX_TURN = math.rad(100) -- per waypoint, away from the edges
local MAX_EDGE_TURN = math.rad(140) -- per waypoint, with the inward bias added
local EDGE_MARGIN = 50 -- how close to an edge before turning inward kicks in
local SAMPLE_STEP = 4 -- points between polyline samples
local BUILD_ATTEMPTS = 6

local function randomIn(range)
	return range.min + math.random() * (range.max - range.min)
end

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

-- Wraps an angle into (-pi, pi].
local function wrapAngle(angle)
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- 0 well inside the bounds, rising to 1 at an edge.
local function edgeProximity(x, y, bounds)
	local nearest = math.min(x - bounds.minX, bounds.maxX - x, y - bounds.minY, bounds.maxY - y)
	return clamp(1 - nearest / EDGE_MARGIN, 0, 1)
end

local function pickWaypoints(fromX, fromY, heading, bounds)
	local centerX = (bounds.minX + bounds.maxX) / 2
	local centerY = (bounds.minY + bounds.maxY) / 2
	local xs, ys = { fromX }, { fromY }
	local x, y = fromX, fromY
	for i = 1, math.random(WAYPOINTS.min, WAYPOINTS.max) do
		-- No random turn on the first leg, so the route sets off along heading.
		local inward = wrapAngle(math.atan2(centerY - y, centerX - x) - heading)
		local turn = inward * edgeProximity(x, y, bounds)
		if i > 1 then
			turn = turn + (math.random() * 2 - 1) * MAX_TURN
		end
		heading = heading + clamp(turn, -MAX_EDGE_TURN, MAX_EDGE_TURN)
		local leg = randomIn(LEG)
		x = x + math.cos(heading) * leg
		y = y + math.sin(heading) * leg
		xs[#xs + 1], ys[#ys + 1] = x, y
	end
	return xs, ys
end

-- Uniform Catmull-Rom between p1 and p2 at t in [0, 1].
local function catmullRom(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
end

-- Phantom end points: the start one makes the curve leave along heading
-- (tangent at P1 is (P2 - P0) / 2), the end one extrapolates the last leg.
local function sampleSpline(xs, ys, heading)
	local n = #xs
	local firstLeg = math.sqrt((xs[2] - xs[1]) ^ 2 + (ys[2] - ys[1]) ^ 2)
	local cx = { xs[2] - 2 * firstLeg * math.cos(heading) }
	local cy = { ys[2] - 2 * firstLeg * math.sin(heading) }
	for i = 1, n do
		cx[#cx + 1], cy[#cy + 1] = xs[i], ys[i]
	end
	cx[#cx + 1] = 2 * xs[n] - xs[n - 1]
	cy[#cy + 1] = 2 * ys[n] - ys[n - 1]

	local outX, outY = { xs[1] }, { ys[1] }
	for i = 2, #cx - 2 do
		local chord = math.sqrt((cx[i + 1] - cx[i]) ^ 2 + (cy[i + 1] - cy[i]) ^ 2)
		local steps = math.max(1, math.ceil(chord / SAMPLE_STEP))
		for step = 1, steps do
			local t = step / steps
			outX[#outX + 1] = catmullRom(cx[i - 1], cx[i], cx[i + 1], cx[i + 2], t)
			outY[#outY + 1] = catmullRom(cy[i - 1], cy[i], cy[i + 1], cy[i + 2], t)
		end
	end
	return outX, outY, math.atan2(ys[n] - ys[n - 1], xs[n] - xs[n - 1])
end

local function inBounds(xs, ys, bounds)
	for i = 1, #xs do
		if xs[i] < bounds.minX or xs[i] > bounds.maxX or ys[i] < bounds.minY or ys[i] > bounds.maxY then
			return false
		end
	end
	return true
end

-- heading: radians to set off along, or nil for a random direction. Retries
-- routes that leave the bounds, and clamps the last attempt as a fallback.
-- Returns { xs, ys, lengths, total, endHeading, keptHeading }.
function WanderRoute.build(fromX, fromY, heading, bounds)
	local xs, ys, endHeading, keptHeading
	for attempt = 1, BUILD_ATTEMPTS do
		-- Gives up on the given heading for the later attempts.
		local startHeading = (attempt <= BUILD_ATTEMPTS / 2 and heading) or math.random() * 2 * math.pi
		local waypointXs, waypointYs = pickWaypoints(fromX, fromY, startHeading, bounds)
		xs, ys, endHeading = sampleSpline(waypointXs, waypointYs, startHeading)
		keptHeading = heading ~= nil and startHeading == heading
		if inBounds(xs, ys, bounds) then
			break
		end
	end
	for i = 1, #xs do
		xs[i] = clamp(xs[i], bounds.minX, bounds.maxX)
		ys[i] = clamp(ys[i], bounds.minY, bounds.maxY)
	end

	local lengths = { 0 }
	for i = 2, #xs do
		lengths[i] = lengths[i - 1] + math.sqrt((xs[i] - xs[i - 1]) ^ 2 + (ys[i] - ys[i - 1]) ^ 2)
	end
	return { xs = xs, ys = ys, lengths = lengths, total = lengths[#lengths], endHeading = endHeading, keptHeading = keptHeading, cursor = 1 }
end

-- Position at a distance along the route, plus the unit x-direction of travel
-- there. Distances must only grow between calls (a cursor walks forward).
function WanderRoute.sample(route, distance)
	local xs, ys, lengths = route.xs, route.ys, route.lengths
	local i = route.cursor
	while i < #xs - 1 and lengths[i + 1] < distance do
		i = i + 1
	end
	route.cursor = i
	local span = lengths[i + 1] - lengths[i]
	local t = span > 0 and clamp((distance - lengths[i]) / span, 0, 1) or 1
	local dx, dy = xs[i + 1] - xs[i], ys[i + 1] - ys[i]
	local dirX = span > 0 and dx / span or 0
	return xs[i] + dx * t, ys[i] + dy * t, dirX
end

return WanderRoute
