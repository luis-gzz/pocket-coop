-- Depth-sorts world objects by their bottom edge (ADR-0006): whichever
-- registered object's depth is largest renders frontmost. Generic by design
-- - any world object (chicken, dropping, or a future type) just needs a
-- toFront() method; depth defaults to the object's raw .y (its center, since
-- display objects are center-anchored by default) unless the caller
-- supplies a getDepth that reaches its actual bottom edge instead.
local YSort = {}

local worldGroup = nil
local entries = {}

-- The floor layer (ADR-0014): a separate group created and inserted below
-- worldGroup, so anything registered here (hen beds) sorts against its own
-- kind but always renders behind every object in worldGroup regardless of
-- position - a toFront() here only ever reorders floorGroup's own children,
-- never worldGroup's.
local floorGroup = nil
local floorEntries = {}

local function defaultGetDepth(object)
	return object.y
end

-- Creates the shared group world objects should be inserted into. Call once,
-- after the background layer and before any world object is created, so the
-- group as a whole sits above the background and below anything created
-- after it (UI overlays).
function YSort.createGroup()
	worldGroup = display.newGroup()
	return worldGroup
end

function YSort.getGroup()
	return worldGroup
end

-- getDepth(object), if given, computes the object's bottom-edge y instead of
-- using its raw (center) .y.
function YSort.add(object, getDepth)
	table.insert(entries, { object = object, getDepth = getDepth or defaultGetDepth })
end

function YSort.remove(object)
	for index, entry in ipairs(entries) do
		if entry.object == object then
			table.remove(entries, index)
			return
		end
	end
end

-- Call once, after createGroup's background layer and before createGroup
-- itself, so floorGroup sits behind worldGroup in the display tree.
function YSort.createFloorLayer()
	floorGroup = display.newGroup()
	return floorGroup
end

function YSort.getFloorGroup()
	return floorGroup
end

function YSort.addToFloor(object, getDepth)
	table.insert(floorEntries, { object = object, getDepth = getDepth or defaultGetDepth })
end

function YSort.removeFromFloor(object)
	for index, entry in ipairs(floorEntries) do
		if entry.object == object then
			table.remove(floorEntries, index)
			return
		end
	end
end

local function resortEntries(list)
	table.sort(list, function(a, b)
		return a.getDepth(a.object) < b.getDepth(b.object)
	end)
	for _, entry in ipairs(list) do
		entry.object:toFront()
	end
end

-- Which list resorts first doesn't matter for floorGroup vs. worldGroup
-- stacking - toFront() only reorders children within their own group, so
-- that's fixed entirely by which group was created first (see
-- YSort.createFloorLayer's own comment). Both just need resorting each frame.
local function resort()
	resortEntries(floorEntries)
	resortEntries(entries)
end

Runtime:addEventListener("enterFrame", resort)

return YSort
