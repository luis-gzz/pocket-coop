local Catalog = require("src.ui.catalog")

-- Which slot of the toolbar or the barn each item sits in (CONTEXT.md's
-- Barn). Slots are positional and may be empty. Every item type is in
-- exactly one slot; items are infinite, so only the type moves, never a count.
local Inventory = {}

Inventory.TOOLBAR_SLOTS = 10
Inventory.BARN_SLOTS = 30

local SIZES = { toolbar = Inventory.TOOLBAR_SLOTS, barn = Inventory.BARN_SLOTS }

local areas = { toolbar = {}, barn = {} } -- [area][index] = item type or nil
local onSave = nil
local listeners = {}

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

-- saved: { toolbar = { type or "" }, barn = { type or "" } }, or nil for an
-- old save. Saved positions are kept; unknown or repeated types are dropped,
-- and catalog items in neither take the first open toolbar slot, else the barn.
function Inventory.load(saved)
	saved = saved or {}
	local known = {}
	for _, item in ipairs(Catalog) do
		known[item.type] = true
	end

	areas = { toolbar = {}, barn = {} }
	local placed = {}
	for area, size in pairs(SIZES) do
		for index, itemType in ipairs(saved[area] or {}) do
			if index <= size and known[itemType] and not placed[itemType] then
				areas[area][index] = itemType
				placed[itemType] = true
			end
		end
	end
	for _, item in ipairs(Catalog) do
		if not placed[item.type] then
			local area = firstOpen("toolbar") and "toolbar" or "barn"
			areas[area][firstOpen(area)] = item.type
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

-- A fixture returned from the map: stays where its type already is, else
-- takes the first open toolbar slot, else the first open barn slot.
-- Returns the area and index it ended up in.
function Inventory.returnItem(itemType)
	local area, index = Inventory.find(itemType)
	if area then
		return area, index
	end
	area = firstOpen("toolbar") and "toolbar" or "barn"
	index = firstOpen(area)
	areas[area][index] = itemType
	changed()
	return area, index
end

function Inventory.getSaveData()
	local data = {}
	for area, size in pairs(SIZES) do
		data[area] = {}
		for index = 1, size do
			data[area][index] = areas[area][index] or ""
		end
	end
	return data
end

return Inventory
