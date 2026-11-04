local Constants = require("src.util.constants")
local Color = require("src.util.color")
local Font = require("src.ui.font")
local Layout = require("src.ui.layout")
local Catalog = require("src.ui.catalog")
local Inventory = require("src.systems.inventory")
local Selection = require("src.ui.selection")
local Slot = require("src.ui.slot")

-- The barn's panel (CONTEXT.md's Barn): a grid of stored items, opened from
-- the toolbar's barn slot. Tap an item, then Take out to return it to the
-- toolbar. Closed by any tap outside it; the game keeps running behind it.
local BarnPanel = {}

-- Spatial constants are native * Constants.PIXEL_SCALE, like every other
-- piece of UI in the project.
local COLUMNS = 4
local SLOT_GAP = 3 * Constants.PIXEL_SCALE
local PANEL_PADDING = 6 * Constants.PIXEL_SCALE
local PANEL_CORNER_RADIUS = 3 * Constants.PIXEL_SCALE
local PANEL_STROKE_WIDTH = 1 * Constants.PIXEL_SCALE
local TITLE_GAP = 5 * Constants.PIXEL_SCALE
local BUTTON_GAP = 5 * Constants.PIXEL_SCALE
local BUTTON_WIDTH = 40 * Constants.PIXEL_SCALE
local BUTTON_HEIGHT = 14 * Constants.PIXEL_SCALE
local BUTTON_CORNER_RADIUS = 2 * Constants.PIXEL_SCALE

-- Shared with src/ui/tooltip.lua's and welcome_card.lua's panels.
local PANEL_FILL_HEX = "f2f0e5"
local PANEL_STROKE_HEX = "3a3858"
local BUTTON_FILL_HEX = "8ab060"

local itemsByType = {}
for _, item in ipairs(Catalog) do
	itemsByType[item.type] = item
end

local current = nil -- { dismiss, group }
local picked = nil -- the item type whose Take out button shows

function BarnPanel.isOpen()
	return current ~= nil
end

function BarnPanel.hide()
	if not current then
		return
	end
	current.dismiss:removeSelf()
	current.group:removeSelf()
	current = nil
	picked = nil
end

local function addText(group, text, y)
	local label = display.newText(group, text, 0, 0, Constants.FONT, Constants.FONT_SIZE_SMALL)
	Font.placeCapsAt(label, y, Constants.FONT_SIZE_SMALL)
	label:setFillColor(0.2, 0.2, 0.2)
	return label
end

local function build()
	local group = current.group
	for i = group.numChildren, 1, -1 do
		group[i]:removeSelf()
	end

	local barn = Inventory.getBarn()
	local columns = math.max(1, math.min(COLUMNS, #barn))
	local rows = math.ceil(#barn / COLUMNS)
	local gridWidth = columns * Slot.SIZE + (columns - 1) * SLOT_GAP
	local gridHeight = rows * Slot.SIZE + math.max(0, rows - 1) * SLOT_GAP

	local width = math.max(COLUMNS * Slot.SIZE + (COLUMNS - 1) * SLOT_GAP, BUTTON_WIDTH) + PANEL_PADDING * 2
	local titleHeight = Font.capHeight(Constants.FONT_SIZE_SMALL)
	local bodyHeight = #barn > 0 and gridHeight or titleHeight
	local height = PANEL_PADDING * 2 + titleHeight + TITLE_GAP + bodyHeight
		+ (picked and BUTTON_GAP + BUTTON_HEIGHT or 0)

	local panel = display.newRoundedRect(group, 0, 0, width, height, PANEL_CORNER_RADIUS)
	panel:setFillColor(Color.hexToRGB(PANEL_FILL_HEX))
	panel.strokeWidth = PANEL_STROKE_WIDTH
	panel:setStrokeColor(Color.hexToRGB(PANEL_STROKE_HEX))
	-- Taps on the panel itself do nothing, rather than closing it.
	panel:addEventListener("tap", function()
		return true
	end)

	local top = -height / 2 + PANEL_PADDING
	addText(group, "Barn", top)
	local bodyTop = top + titleHeight + TITLE_GAP

	if #barn == 0 then
		addText(group, "Barn is empty", bodyTop)
		return
	end

	for index, itemType in ipairs(barn) do
		local column = (index - 1) % COLUMNS
		local row = math.floor((index - 1) / COLUMNS)
		local slot = Slot.new(group, -gridWidth / 2 + column * (Slot.SIZE + SLOT_GAP),
			bodyTop + row * (Slot.SIZE + SLOT_GAP), itemsByType[itemType])
		slot.setSelected(itemType == picked)
		slot.background:addEventListener("tap", function()
			picked = itemType ~= picked and itemType or nil
			build()
			return true
		end)
	end

	if picked then
		local buttonY = bodyTop + gridHeight + BUTTON_GAP + BUTTON_HEIGHT / 2
		local button = display.newRoundedRect(group, 0, buttonY, BUTTON_WIDTH, BUTTON_HEIGHT, BUTTON_CORNER_RADIUS)
		button:setFillColor(Color.hexToRGB(BUTTON_FILL_HEX))
		button.strokeWidth = PANEL_STROKE_WIDTH
		button:setStrokeColor(Color.hexToRGB(PANEL_STROKE_HEX))
		local label = display.newText(group, "Take out", 0, 0, Constants.FONT, Constants.FONT_SIZE_SMALL)
		Font.centerCapsOn(label, buttonY, Constants.FONT_SIZE_SMALL)
		label:setFillColor(0.2, 0.2, 0.2)
		button:addEventListener("tap", function()
			local itemType = picked
			picked = nil
			Inventory.takeOut(itemType)
			build()
			return true
		end)
	end
end

function BarnPanel.show()
	BarnPanel.hide()
	Selection.clear()

	local centerX = display.screenOriginX + display.actualContentWidth / 2
	local centerY = display.screenOriginY + display.actualContentHeight / 2

	-- Full-screen catcher, as in welcome_card.lua: swallows touches, and its
	-- tap listener is attached a frame late so the opening tap doesn't close it.
	local dismiss = display.newRect(centerX, centerY, display.actualContentWidth, display.actualContentHeight)
	dismiss:setFillColor(0, 0, 0, 0.01)
	dismiss:addEventListener("touch", function()
		return true
	end)
	timer.performWithDelay(1, function()
		pcall(function()
			dismiss:addEventListener("tap", function()
				BarnPanel.hide()
				return true
			end)
		end)
	end)

	local bounds = Layout.getPlayArea()
	local group = display.newGroup()
	group.x, group.y = (bounds.minX + bounds.maxX) / 2, (bounds.minY + bounds.maxY) / 2

	current = { dismiss = dismiss, group = group }
	build()
end

function BarnPanel.toggle()
	if current then
		BarnPanel.hide()
	else
		BarnPanel.show()
	end
end

return BarnPanel
