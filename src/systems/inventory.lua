local Catalog = require("src.ui.catalog")

-- Which items sit in the toolbar and which in the barn (CONTEXT.md's Barn).
-- Every item is in exactly one of the two; items are infinite, so only the
-- type moves, never a count.
local Inventory = {}

local toolbar = {} -- ordered item types, fixtures first
local inBarn = {} -- set of item types
local onSave = nil
local listeners = {}

local fixtureTypes = {}
for _, item in ipairs(Catalog) do
	fixtureTypes[item.type] = item.fixture
end

-- Fixtures always lead the toolbar; within each group the order is kept.
local function insertIntoToolbar(itemType)
	local index = #toolbar + 1
	if fixtureTypes[itemType] then
		index = 1
		while toolbar[index] and fixtureTypes[toolbar[index]] do
			index = index + 1
		end
	end
	table.insert(toolbar, index, itemType)
end

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

-- saved: { toolbar = { types }, barn = { types } }, or nil for an old save.
-- Unknown types are dropped; catalog items in neither list join the end of
-- their group, so new items show up where the player sees them.
function Inventory.load(saved)
	saved = saved or {}
	local known = {}
	for _, item in ipairs(Catalog) do
		known[item.type] = true
	end

	toolbar, inBarn = {}, {}
	local placed = {}
	for _, itemType in ipairs(saved.toolbar or {}) do
		if known[itemType] and not placed[itemType] then
			insertIntoToolbar(itemType)
			placed[itemType] = true
		end
	end
	for _, itemType in ipairs(saved.barn or {}) do
		if known[itemType] and not placed[itemType] then
			inBarn[itemType] = true
			placed[itemType] = true
		end
	end
	for _, item in ipairs(Catalog) do
		if not placed[item.type] then
			insertIntoToolbar(item.type)
		end
	end
end

function Inventory.getToolbar()
	return toolbar
end

-- Barn items in catalog order.
function Inventory.getBarn()
	local items = {}
	for _, item in ipairs(Catalog) do
		if inBarn[item.type] then
			table.insert(items, item.type)
		end
	end
	return items
end

function Inventory.store(itemType)
	for i, toolbarType in ipairs(toolbar) do
		if toolbarType == itemType then
			table.remove(toolbar, i)
			inBarn[itemType] = true
			changed()
			return
		end
	end
end

function Inventory.takeOut(itemType)
	if not inBarn[itemType] then
		return
	end
	inBarn[itemType] = nil
	insertIntoToolbar(itemType)
	changed()
end

function Inventory.getSaveData()
	local barn = Inventory.getBarn()
	local savedToolbar = {}
	for i, itemType in ipairs(toolbar) do
		savedToolbar[i] = itemType
	end
	return { toolbar = savedToolbar, barn = barn }
end

return Inventory
