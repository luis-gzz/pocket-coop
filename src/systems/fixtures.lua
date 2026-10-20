local Layout = require("src.ui.layout")
local Footprints -- required lazily: it reads this module's records

-- Shared spacing for fixtures (CONTEXT.md): hen beds and water bowls.
-- Each owner registers its list of { x, y, width, height, footprintShare }
-- records (ADR-0014, ADR-0021).
local Fixtures = {}

local sources = {}
-- Lists of { x, y, width, height } world objects a footprint can't cover.
local itemSources = {}
local changeListeners = {}

-- getRecords is re-read on every check, since load() replaces lists wholesale.
function Fixtures.register(getRecords)
	table.insert(sources, getRecords)
end

-- getItems: like register, for things a fixture can't be dropped on top of.
function Fixtures.registerItems(getItems)
	table.insert(itemSources, getItems)
end

function Fixtures.all()
	local records = {}
	for _, getRecords in ipairs(sources) do
		for _, record in ipairs(getRecords()) do
			table.insert(records, record)
		end
	end
	return records
end

-- listener() runs after any fixture is placed or moved.
function Fixtures.onChanged(listener)
	table.insert(changeListeners, listener)
end

function Fixtures.notifyChanged()
	for _, listener in ipairs(changeListeners) do
		listener()
	end
end

local function coversItem(x, y, record)
	Footprints = Footprints or require("src.systems.footprints")
	for _, getItems in ipairs(itemSources) do
		for _, item in ipairs(getItems()) do
			if Footprints.wouldCover(record, x, y, item.x, item.y, item.width, item.height) then
				return true
			end
		end
	end
	return false
end

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function isWithinPlayArea(x, y, width, height)
	local bounds = Layout.getPlayArea()
	return x - width / 2 >= bounds.minX
		and x + width / 2 <= bounds.maxX
		and y - height / 2 >= bounds.minY
		and y + height / 2 <= bounds.maxY
end

local function clampToPlayArea(x, y, width, height)
	local bounds = Layout.getPlayArea()
	return clamp(x, bounds.minX + width / 2, bounds.maxX - width / 2),
		clamp(y, bounds.minY + height / 2, bounds.maxY - height / 2)
end

-- The "directly on top of each other" zone: within the pair's average half
-- size on both axes at once (a bed against a bed is its own half size).
local function zone(width, height, other)
	return (width + other.width) / 4, (height + other.height) / 4
end

local function findOverlapping(x, y, width, height, exclude)
	for _, getRecords in ipairs(sources) do
		for _, other in ipairs(getRecords()) do
			local zoneX, zoneY = zone(width, height, other)
			if other ~= exclude and math.abs(x - other.x) < zoneX and math.abs(y - other.y) < zoneY then
				return other
			end
		end
	end
	return nil
end

-- Pushes (x, y) out of `other`'s zone along whichever axis needs the
-- smaller push; a coincident pair picks a random direction.
local function separate(x, y, width, height, other)
	local dx, dy = x - other.x, y - other.y
	if dx == 0 and dy == 0 then
		local angle = math.random() * math.pi * 2
		dx, dy = math.cos(angle), math.sin(angle)
	end

	local zoneX, zoneY = zone(width, height, other)
	if zoneX - math.abs(dx) <= zoneY - math.abs(dy) then
		local sign = (dx > 0) and 1 or (dx < 0) and -1 or ((math.random() < 0.5) and 1 or -1)
		return other.x + sign * zoneX, y
	end

	local sign = (dy > 0) and 1 or (dy < 0) and -1 or ((math.random() < 0.5) and 1 or -1)
	return x, other.y + sign * zoneY
end

-- Final (x, y) for a fixture placement or drag, or nil, nil if any part
-- would leave the play area or its footprint would cover an item.
-- exclude is the record itself when dragging; footprintShare is its type's.
function Fixtures.resolve(x, y, width, height, footprintShare, exclude)
	if not isWithinPlayArea(x, y, width, height) then
		return nil, nil
	end

	local overlapping = findOverlapping(x, y, width, height, exclude)
	if overlapping then
		x, y = separate(x, y, width, height, overlapping)
		x, y = clampToPlayArea(x, y, width, height)
	end

	if coversItem(x, y, { width = width, height = height, footprintShare = footprintShare }) then
		return nil, nil
	end
	return x, y
end

return Fixtures
