local Catalog = require("src.ui.catalog")

-- Which slot of the toolbar or the barn each item sits in (CONTEXT.md's
-- Barn), and each item's stock (CONTEXT.md's Stock). Slots are positional
-- and may be empty. An item is in exactly one slot while it has stock;
-- tools have no stock and never leave their slot.
local Inventory = {}

Inventory.TOOLBAR_SLOTS = 10
Inventory.BARN_SLOTS = 30

local SIZES = { toolbar = Inventory.TOOLBAR_SLOTS, barn = Inventory.BARN_SLOTS }

local itemsByType = {}
for _, item in ipairs(Catalog) do
	itemsByType[item.type] = item
end

local areas = { toolbar = {}, barn = {} } -- [area][index] = item type or nil
local counts = {} -- [item type] = stock, for every non-tool
local onSave = nil
local listeners = {}
local ranOutListeners = {}

local function changed()
	if onSave then
		onSave()
	end
	for _, listener in ipairs(listeners) do
		listener()
	end
end

function Inventory.setSaveCallback(fn)
	onSave = fn
end

function Inventory.onChanged(listener)
	table.insert(listeners, listener)
end

-- listener(area, index, itemType): that slot just emptied because its item ran out.
function Inventory.onRanOut(listener)
	table.insert(ranOutListeners, listener)
end

function Inventory.isTool(itemType)
	return itemsByType[itemType] ~= nil and itemsByType[itemType].tool == true
end

-- An item's stock; nil for a tool.
function Inventory.count(itemType)
	if Inventory.isTool(itemType) then
		return nil
	end
	return counts[itemType] or 0
end

local function firstOpen(area)
	for index = 1, SIZES[area] do
		if not areas[area][index] then
			return index
		end
	end
	return nil
end

-- Where an item type sits: area, index - or nil if nowhere.
function Inventory.find(itemType)
	for area, slots in pairs(areas) do
		for index = 1, SIZES[area] do
			if slots[index] == itemType then
				return area, index
			end
		end
	end
	return nil
end

local function hasStock(itemType)
	return Inventory.isTool(itemType) or (counts[itemType] or 0) > 0
end

-- Puts an item in the first open toolbar slot, else the first open barn slot.
local function slotIn(itemType)
	local area = firstOpen("toolbar") and "toolbar" or "barn"
	local index = firstOpen(area)
	areas[area][index] = itemType
	return area, index
end

-- saved: { toolbar = { type or "" }, barn = { type or "" }, counts = { [type] = n } },
-- or nil. defaultCounts is used when the save has no counts (a new game or a
-- save from before stock). Saved positions are kept; unknown, repeated, or
-- out-of-stock types are dropped, and stocked ones in neither take the first
-- open toolbar slot, else the barn.
function Inventory.load(saved, defaultCounts)
	saved = saved or {}
	counts = {}
	for itemType, count in pairs(saved.counts or defaultCounts or {}) do
		if itemsByType[itemType] and not Inventory.isTool(itemType) then
			counts[itemType] = math.max(0, math.floor(tonumber(count) or 0))
		end
	end

	areas = { toolbar = {}, barn = {} }
	local placed = {}
	for area, size in pairs(SIZES) do
		for index, itemType in ipairs(saved[area] or {}) do
			if index <= size and itemsByType[itemType] and not placed[itemType] and hasStock(itemType) then
				areas[area][index] = itemType
				placed[itemType] = true
			end
		end
	end
	for _, item in ipairs(Catalog) do
		if not placed[item.type] and hasStock(item.type) then
			slotIn(item.type)
		end
	end
end

-- The item type in a slot, or nil if it's empty.
function Inventory.get(area, index)
	return areas[area][index]
end

-- Moves a slot's item to another slot, swapping with whatever is there.
function Inventory.move(fromArea, fromIndex, toArea, toIndex)
	if fromArea == toArea and fromIndex == toIndex then
		return
	end
	local moving = areas[fromArea][fromIndex]
	areas[fromArea][fromIndex] = areas[toArea][toIndex]
	areas[toArea][toIndex] = moving
	changed()
end

-- Takes one of an item for a use. The last one empties its slot (see
-- onRanOut). A tool is never used up.
function Inventory.consume(itemType)
	if Inventory.isTool(itemType) or (counts[itemType] or 0) <= 0 then
		return
	end
	counts[itemType] = counts[itemType] - 1
	local area, index
	if counts[itemType] == 0 then
		area, index = Inventory.find(itemType)
		if area then
			areas[area][index] = nil
		end
	end
	changed()
	if area then
		for _, listener in ipairs(ranOutListeners) do
			listener(area, index, itemType)
		end
	end
end

-- Adds n to an item's stock (bought, or taken back off the map). It stays
-- where it is, else takes the first open toolbar slot, else the first open
-- barn slot. Returns the area and index it's in.
function Inventory.add(itemType, n)
	if not Inventory.isTool(itemType) then
		counts[itemType] = (counts[itemType] or 0) + (n or 1)
	end
	local area, index = Inventory.find(itemType)
	if not area then
		area, index = slotIn(itemType)
	end
	changed()
	return area, index
end

function Inventory.getSaveData()
	local data = { counts = {} }
	for area, size in pairs(SIZES) do
		data[area] = {}
		for index = 1, size do
			data[area][index] = areas[area][index] or ""
		end
	end
	for itemType, count in pairs(counts) do
		data.counts[itemType] = count
	end
	return data
end

return Inventory
