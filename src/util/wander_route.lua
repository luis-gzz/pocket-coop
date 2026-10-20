-- Plans a chicken's wander route: a random walk of waypoints run through a
-- Catmull-Rom spline, sampled into a polyline the chicken follows by distance.
-- Also turns a detour's corner points into a rounded route (fromPoints).
local WanderRoute = {}

local WAYPOINTS = { min = 3, max = 5 }
local LEG = { min = 25, max = 45 } -- points between waypoints
local MAX_TURN = math.rad(100) -- per waypoint, away from the edges
local MAX_EDGE_TURN = math.rad(140) -- per waypoint, with the inward bias added
local EDGE_MARGIN = 50 -- how close to an edge before turning inward kicks in
local SAMPLE_STEP = 4 -- points between polyline samples
local BUILD_ATTEMPTS = 6
-- How far before and after a corner a rounded route starts curving.
local CORNER_RADIUS = 12

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

-- avoid (optional) is { blocked(x, y) } for spots the route mustn't cross.
local function isClear(xs, ys, bounds, avoid)
	for i = 1, #xs do
		if xs[i] < bounds.minX or xs[i] > bounds.maxX or ys[i] < bounds.minY or ys[i] > bounds.maxY then
			return false
		end
		if avoid and i > 1 and avoid.blocked(xs[i], ys[i]) then
			return false
		end
	end
	return true
end

local function toRoute(xs, ys, extra)
	local lengths = { 0 }
	for i = 2, #xs do
		lengths[i] = lengths[i - 1] + math.sqrt((xs[i] - xs[i - 1]) ^ 2 + (ys[i] - ys[i - 1]) ^ 2)
	end
	local route = { xs = xs, ys = ys, lengths = lengths, total = lengths[#lengths], cursor = 1 }
	for key, value in pairs(extra or {}) do
		route[key] = value
	end
	return route
end

-- Rounds each interior corner with a quadratic curve, then samples it.
local function roundCorners(xs, ys)
	local outX, outY = { xs[1] }, { ys[1] }
	for i = 2, #xs - 1 do
		local inLength = math.sqrt((xs[i] - xs[i - 1]) ^ 2 + (ys[i] - ys[i - 1]) ^ 2)
		local outLength = math.sqrt((xs[i + 1] - xs[i]) ^ 2 + (ys[i + 1] - ys[i]) ^ 2)
		local radius = math.min(CORNER_RADIUS, inLength / 2, outLength / 2)
		if radius <= 0 then
			outX[#outX + 1], outY[#outY + 1] = xs[i], ys[i]
		else
			local ax = xs[i] - (xs[i] - xs[i - 1]) / inLength * radius
			local ay = ys[i] - (ys[i] - ys[i - 1]) / inLength * radius
			local bx = xs[i] + (xs[i + 1] - xs[i]) / outLength * radius
			local by = ys[i] + (ys[i + 1] - ys[i]) / outLength * radius
			local steps = math.max(2, math.ceil(radius * 2 / SAMPLE_STEP))
			for step = 0, steps do
				local t = step / steps
				local u = 1 - t
				outX[#outX + 1] = u * u * ax + 2 * u * t * xs[i] + t * t * bx
				outY[#outY + 1] = u * u * ay + 2 * u * t * ys[i] + t * t * by
			end
		end
	end
	outX[#outX + 1], outY[#outY + 1] = xs[#xs], ys[#ys]
	return outX, outY
end

-- A route through a list of {x, y} points (a detour), corners rounded.
function WanderRoute.fromPoints(points)
	local xs, ys = {}, {}
	for i, point in ipairs(points) do
		xs[i], ys[i] = point.x, point.y
	end
	if #xs == 1 then
		xs[2], ys[2] = xs[1], ys[1]
	end
	xs, ys = roundCorners(xs, ys)
	return toRoute(xs, ys)
end

-- Last resort once every attempt crosses a footprint: moves blocked
-- waypoints out, splices a detour into each leg, and follows that.
local function detourWaypoints(waypointXs, waypointYs, heading, avoid)
	local xs, ys = { waypointXs[1] }, { waypointYs[1] }
	for i = 2, #waypointXs do
		local toX, toY = avoid.pushOut(waypointXs[i], waypointYs[i])
		local points = avoid.detour(xs[#xs], ys[#ys], toX, toY)
		for j = 2, #points do
			xs[#xs + 1], ys[#ys + 1] = points[j].x, points[j].y
		end
	end
	local splineXs, splineYs, endHeading = sampleSpline(xs, ys, heading)
	if not isClear(splineXs, splineYs, { minX = -math.huge, maxX = math.huge, minY = -math.huge, maxY = math.huge }, avoid) then
		splineXs, splineYs = roundCorners(xs, ys)
	end
	return splineXs, splineYs, endHeading
end

-- heading: radians to set off along, or nil for a random direction. Retries
-- routes that leave the bounds or cross what avoid blocks (if given), then
-- detours around footprints and clamps the last attempt as a fallback.
-- avoid: { blocked(x, y), pushOut(x, y), detour(ax, ay, bx, by) -> points }.
-- Returns { xs, ys, lengths, total, endHeading, keptHeading }.
function WanderRoute.build(fromX, fromY, heading, bounds, avoid)
	local xs, ys, endHeading, keptHeading
	local waypointXs, waypointYs, startHeading
	local clear = false
	for attempt = 1, BUILD_ATTEMPTS do
		-- Gives up on the given heading for the later attempts.
		startHeading = (attempt <= BUILD_ATTEMPTS / 2 and heading) or math.random() * 2 * math.pi
		waypointXs, waypointYs = pickWaypoints(fromX, fromY, startHeading, bounds)
		xs, ys, endHeading = sampleSpline(waypointXs, waypointYs, startHeading)
		keptHeading = heading ~= nil and startHeading == heading
		if isClear(xs, ys, bounds, avoid) then
			clear = true
			break
		end
	end
	if not clear and avoid then
		for i = 1, #waypointXs do
			waypointXs[i] = clamp(waypointXs[i], bounds.minX, bounds.maxX)
			waypointYs[i] = clamp(waypointYs[i], bounds.minY, bounds.maxY)
		end
		xs, ys, endHeading = detourWaypoints(waypointXs, waypointYs, startHeading, avoid)
	end
	for i = 1, #xs do
		xs[i] = clamp(xs[i], bounds.minX, bounds.maxX)
		ys[i] = clamp(ys[i], bounds.minY, bounds.maxY)
	end

	return toRoute(xs, ys, { endHeading = endHeading, keptHeading = keptHeading })
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
