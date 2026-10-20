local Fixtures = require("src.systems.fixtures")

-- Fixture footprints (CONTEXT.md, ADR-0021): the part of a fixture nothing
-- rests in and chickens walk around. All y values are ground-contact y (a
-- chicken's feet, an object's bottom edge), not sprite centers.
local Footprints = {}

-- Treats a path brushing a footprint's edge as clear.
local EDGE_EPSILON = 0.01
-- Push-outs land this far past an edge, so the result tests as outside.
local PUSH_EPSILON = 0.5
local PUSH_PASSES = 4

-- The fixture's own footprint: full width, from its top share down to its bottom edge.
function Footprints.rect(record)
	local top = record.y - record.height / 2
	return {
		minX = record.x - record.width / 2,
		maxX = record.x + record.width / 2,
		minY = top + record.height * record.footprintShare,
		maxY = record.y + record.height / 2,
		record = record,
	}
end

-- A fixture's depth (CONTEXT.md's Sort line).
function Footprints.sortLine(record)
	return record.y - record.height / 2 + record.height * record.footprintShare
end

-- Every footprint, grown by padX/padY on each side. exclude is skipped.
local function collectRects(padX, padY, exclude)
	local rects = {}
	for _, record in ipairs(Fixtures.all()) do
		if record ~= exclude then
			local rect = Footprints.rect(record)
			rect.minX, rect.maxX = rect.minX - padX, rect.maxX + padX
			rect.minY, rect.maxY = rect.minY - padY, rect.maxY + padY
			table.insert(rects, rect)
		end
	end
	return rects
end

local function contains(rect, x, y)
	return x > rect.minX and x < rect.maxX and y > rect.minY and y < rect.maxY
end

local function findContaining(rects, x, y)
	for _, rect in ipairs(rects) do
		if contains(rect, x, y) then
			return rect
		end
	end
	return nil
end

-- The fixture whose padded footprint holds (x, y), or nil.
function Footprints.findAt(x, y, padX, padY, exclude)
	local rect = findContaining(collectRects(padX or 0, padY or 0, exclude), x, y)
	return rect and rect.record
end

-- Nearest way out of one rect: any edge, or only the sides if horizontalOnly.
local function exitRect(rect, x, y, horizontalOnly)
	local options = {
		{ rect.minX - PUSH_EPSILON, y, x - rect.minX },
		{ rect.maxX + PUSH_EPSILON, y, rect.maxX - x },
	}
	if not horizontalOnly then
		table.insert(options, { x, rect.minY - PUSH_EPSILON, y - rect.minY })
		table.insert(options, { x, rect.maxY + PUSH_EPSILON, rect.maxY - y })
	end
	table.sort(options, function(a, b)
		return a[3] < b[3]
	end)
	return options[1][1], options[1][2]
end

local function pushOutOf(rects, x, y, horizontalOnly)
	for _ = 1, PUSH_PASSES do
		local rect = findContaining(rects, x, y)
		if not rect then
			break
		end
		x, y = exitRect(rect, x, y, horizontalOnly)
	end
	return x, y
end

-- (x, y) moved out of every padded footprint by the shortest way.
function Footprints.pushOut(x, y, padX, padY)
	return pushOutOf(collectRects(padX or 0, padY or 0), x, y)
end

-- A width x height box centered on (x, y), moved out of every footprint:
-- its center kept out of each footprint grown by half the box.
function Footprints.pushBoxOut(x, y, width, height)
	return pushOutOf(collectRects(width / 2, height / 2), x, y)
end

-- Whether a width x height box centered on (x, y) overlaps a fixture's
-- footprint, placed at (fixtureX, fixtureY) instead of where it is.
function Footprints.wouldCover(record, fixtureX, fixtureY, x, y, width, height)
	local rect = Footprints.rect({
		x = fixtureX, y = fixtureY, width = record.width, height = record.height, footprintShare = record.footprintShare,
	})
	return x + width / 2 > rect.minX and x - width / 2 < rect.maxX
		and y + height / 2 > rect.minY and y - height / 2 < rect.maxY
end

-- Whether segment a-b passes through any rect's interior (Liang-Barsky clip).
local function segmentBlocked(rects, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	for _, rect in ipairs(rects) do
		local t0, t1 = 0, 1
		local inside = true
		local checks = {
			{ -dx, ax - (rect.minX + EDGE_EPSILON) },
			{ dx, (rect.maxX - EDGE_EPSILON) - ax },
			{ -dy, ay - (rect.minY + EDGE_EPSILON) },
			{ dy, (rect.maxY - EDGE_EPSILON) - ay },
		}
		for _, check in ipairs(checks) do
			local p, q = check[1], check[2]
			if p == 0 then
				if q < 0 then
					inside = false
					break
				end
			else
				local t = q / p
				if p < 0 then
					t0 = math.max(t0, t)
				else
					t1 = math.min(t1, t)
				end
				if t0 > t1 then
					inside = false
					break
				end
			end
		end
		if inside and t1 - t0 > 1e-6 then
			return true
		end
	end
	return false
end

local function clampToBounds(bounds, x, y)
	if not bounds then
		return x, y
	end
	return math.max(bounds.minX, math.min(bounds.maxX, x)), math.max(bounds.minY, math.min(bounds.maxY, y))
end

-- Shortest path over the start, goal, and padded corners (a visibility
-- graph). Corners past the bounds are pulled back inside, so a fixture near
-- an edge can still be walked around on that side. An unreachable goal is
-- approached as near as the graph allows, then walked to directly.
local function shortestPath(rects, ax, ay, bx, by, margin, bounds)
	local nodes = { { x = ax, y = ay }, { x = bx, y = by } }
	for _, rect in ipairs(rects) do
		for _, corner in ipairs({
			{ rect.minX - margin, rect.minY - margin }, { rect.maxX + margin, rect.minY - margin },
			{ rect.minX - margin, rect.maxY + margin }, { rect.maxX + margin, rect.maxY + margin },
		}) do
			local x, y = clampToBounds(bounds, corner[1], corner[2])
			if not findContaining(rects, x, y) then
				table.insert(nodes, { x = x, y = y })
			end
		end
	end

	-- Dijkstra; a handful of fixtures keeps this tiny.
	local count = #nodes
	local distance, previous, done = { [1] = 0 }, {}, {}
	for _ = 1, count do
		local current, best = nil, math.huge
		for i = 1, count do
			if not done[i] and distance[i] and distance[i] < best then
				current, best = i, distance[i]
			end
		end
		if not current or current == 2 then
			break
		end
		done[current] = true
		local from = nodes[current]
		for i = 1, count do
			if not done[i] then
				local to = nodes[i]
				local candidate = best + math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2)
				if (not distance[i] or candidate < distance[i]) and not segmentBlocked(rects, from.x, from.y, to.x, to.y) then
					distance[i], previous[i] = candidate, current
				end
			end
		end
	end

	local last = 2
	if not distance[2] then
		local nearest = math.huge
		for i, node in ipairs(nodes) do
			local gap = (node.x - bx) ^ 2 + (node.y - by) ^ 2
			if distance[i] and gap < nearest then
				last, nearest = i, gap
			end
		end
	end
	local path = {}
	local index = last
	while index do
		table.insert(path, 1, nodes[index])
		index = previous[index]
	end
	if last ~= 2 then
		table.insert(path, nodes[2])
	end
	return path
end

-- A walk from a to b around every footprint (ADR-0021), as a list of {x, y}
-- points including both ends. opts: padX/padY grow each footprint (the
-- walker's clearance); margin keeps corners far enough out to round off;
-- bounds drops corners outside the walkable area. A start inside a footprint
-- first steps out the nearest way; a goal inside one (a fixture being used)
-- is entered from its nearer side.
function Footprints.findPath(ax, ay, bx, by, opts)
	local rects = collectRects(opts.padX or 0, opts.padY or 0)
	local startX, startY = pushOutOf(rects, ax, ay)
	local endX, endY = pushOutOf(rects, bx, by, true)

	local path = shortestPath(rects, startX, startY, endX, endY, opts.margin or 0, opts.bounds)
	if startX ~= ax or startY ~= ay then
		table.insert(path, 1, { x = ax, y = ay })
	end
	if endX ~= bx or endY ~= by then
		table.insert(path, { x = bx, y = by })
	end
	return path
end

return Footprints
