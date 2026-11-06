local Constants = require("src.util.constants")
local Color = require("src.util.color")
local Font = require("src.ui.font")
local Catalog = require("src.ui.catalog")
local Inventory = require("src.systems.inventory")
local Selection = require("src.ui.selection")
local Slot = require("src.ui.slot")
local DragLift = require("src.util.drag_lift")
local Frame = require("src.ui.frame")
local Layout = require("src.ui.layout")

-- The barn view (CONTEXT.md's Barn): a full-screen grid, opened from the
-- HUD's barn button. Column one is the toolbar's slots, the other three the
-- barn's. Long-press an item to drag it to another slot (swapping with
-- whatever is there); a quick tap shows its name. The game keeps running,
-- hidden behind it.
local BarnView = {}

-- Spatial constants are native * Constants.PIXEL_SCALE, like every other
-- piece of UI in the project. Every colour is from the palette.
local BARN_COLUMNS = 3
local ROWS = Inventory.TOOLBAR_SLOTS
local SLOT_GAP = 3 * Constants.PIXEL_SCALE
local DIVIDER_GAP = 8 * Constants.PIXEL_SCALE -- between the toolbar column and the barn's
local SCREEN_MARGIN = 6 * Constants.PIXEL_SCALE
local HEADING_GAP = 4 * Constants.PIXEL_SCALE
local TINT_PADDING = 2 * Constants.PIXEL_SCALE
local LABEL_PADDING = 3 * Constants.PIXEL_SCALE
local LABEL_TIME = 1500 -- ms a tapped item's name shows

local BACKDROP_HEX = "e5ceb4"
local INK_HEX = "3a3858"

-- ms; matches the other long-press thresholds (chicken.lua, bed.lua).
local LONG_PRESS_TIME = 350
-- A move past this before the long press fires cancels it.
local TOUCH_SLOP = 10

local CLOSE_ICON_PATH = "assets/ui/close_icon.png"
local CLOSE_ICON_PIXELS = 7

local itemsByType = {}
for _, item in ipairs(Catalog) do
	itemsByType[item.type] = item
end

local current = nil -- { root, grid, cells, label, labelHandle }

function BarnView.isOpen()
	return current ~= nil
end

function BarnView.hide()
	if not current then
		return
	end
	if current.labelHandle then
		timer.cancel(current.labelHandle)
	end
	current.root:removeSelf()
	current = nil
end

local function safeRect()
	local top, left, bottom, right = display.getSafeAreaInsets()
	return {
		minX = display.screenOriginX + left,
		maxX = display.screenOriginX + display.actualContentWidth - right,
		minY = display.screenOriginY + top,
		maxY = display.screenOriginY + display.actualContentHeight - bottom,
	}
end

local function newText(parent, text, x, capsY)
	local label = display.newText(parent, text, x, 0, Constants.FONT, Constants.FONT_SIZE_SMALL)
	Font.placeCapsAt(label, capsY, Constants.FONT_SIZE_SMALL)
	label:setFillColor(Color.hexToRGB(INK_HEX))
	return label
end

local function showName(cell)
	local item = itemsByType[Inventory.get(cell.area, cell.index)]
	if current.label then
		current.label:removeSelf()
		timer.cancel(current.labelHandle)
	end
	local label = display.newGroup()
	current.root:insert(label)
	local text = display.newText(label, item.name, 0, 0, Constants.FONT, Constants.FONT_SIZE_SMALL)
	text:setFillColor(Color.hexToRGB(INK_HEX))
	Font.centerCapsOn(text, 0, Constants.FONT_SIZE_SMALL)
	local box, width, height = Frame.new(label, 0, 0, text.width + LABEL_PADDING * 2,
		Font.capHeight(Constants.FONT_SIZE_SMALL) + LABEL_PADDING * 2)
	box.x, box.y = -width / 2, -height / 2
	box:toBack()
	local bounds = safeRect()
	label.x = math.max(bounds.minX + width / 2, math.min(bounds.maxX - width / 2, cell.x + cell.size / 2))
	label.y = cell.y - height / 2 - SLOT_GAP
	current.label = label
	current.labelHandle = timer.performWithDelay(LABEL_TIME, function()
		label:removeSelf()
		current.label = nil
	end)
end

local function cellAt(x, y)
	for _, cell in ipairs(current.cells) do
		if x >= cell.x and x <= cell.x + cell.size and y >= cell.y and y <= cell.y + cell.size then
			return cell
		end
	end
	return nil
end

-- Long press lifts the item into a ghost above the finger; the slot under the
-- ghost is highlighted; release swaps, or snaps back off-grid.
local function addDrag(cell)
	local background = cell.slot.background
	local item = itemsByType[Inventory.get(cell.area, cell.index)]
	local longPressHandle, startX, startY, ghost, hoverCell, lift

	local function setHover(target)
		if hoverCell then
			hoverCell.slot.setSelected(false)
		end
		hoverCell = target
		if hoverCell then
			hoverCell.slot.setSelected(true)
		end
	end

	background:addEventListener("touch", function(event)
		if event.phase == "began" then
			display.getCurrentStage():setFocus(background, event.id)
			background.isFocus = true
			startX, startY = event.x, event.y
			longPressHandle = timer.performWithDelay(LONG_PRESS_TIME, function()
				longPressHandle = nil
				if not current then
					return
				end
				cell.slot.icon.isVisible = false
				local centerX, centerY = cell.x + cell.size / 2, cell.y + cell.size / 2
				ghost = Slot.newIcon(current.root, item, centerX, centerY, cell.size)
				setHover(cell)
				lift = DragLift.begin(centerX, centerY, startX, startY, ghost.height / 2, function(x, y)
					ghost.x, ghost.y = x, y
					setHover(cellAt(x, y))
				end)
			end)
		elseif background.isFocus then
			if event.phase == "moved" then
				if ghost then
					DragLift.move(lift, event.x, event.y)
				elseif longPressHandle then
					local dx, dy = event.x - startX, event.y - startY
					if dx * dx + dy * dy > TOUCH_SLOP * TOUCH_SLOP then
						timer.cancel(longPressHandle)
						longPressHandle = nil
					end
				end
			elseif event.phase == "ended" or event.phase == "cancelled" then
				display.getCurrentStage():setFocus(background, nil)
				background.isFocus = false
				if longPressHandle then
					timer.cancel(longPressHandle)
					longPressHandle = nil
					if event.phase == "ended" then
						showName(cell)
					end
				elseif ghost then
					DragLift.finish(lift)
					lift = nil
					local target = event.phase == "ended" and hoverCell or nil
					setHover(nil)
					ghost:removeSelf()
					ghost = nil
					if target and target ~= cell then
						Inventory.move(cell.area, cell.index, target.area, target.index)
					else
						cell.slot.icon.isVisible = true
					end
				end
			end
		end
		return true
	end)
end

local function buildGrid()
	if current.grid then
		current.grid:removeSelf()
	end
	local grid = display.newGroup()
	current.root:insert(grid)
	current.grid = grid
	current.cells = {}

	local layout = current.layout
	for row = 1, ROWS do
		for column = 1, 1 + BARN_COLUMNS do
			local area = column == 1 and "toolbar" or "barn"
			local index = column == 1 and row or (row - 1) * BARN_COLUMNS + column - 1
			local x = layout.columnX[column]
			local y = layout.gridTop + (row - 1) * (layout.size + SLOT_GAP)
			local itemType = Inventory.get(area, index)
			local cell = {
				area = area, index = index, x = x, y = y, size = layout.size,
				slot = Slot.new(grid, x, y, itemsByType[itemType], layout.size),
			}
			table.insert(current.cells, cell)
			if itemType then
				addDrag(cell)
			end
		end
	end
	if current.label then
		current.label:toFront()
	end
end

-- Slot size and column positions that fit the safe area. The divider gap
-- widens so the "Toolbar" heading, centered over its column, never crosses it.
local function computeLayout(bounds, headingHeight, toolbarHeadingWidth)
	local gridTop = Layout.getHudRect().maxY + HEADING_GAP + headingHeight + HEADING_GAP
	local availableHeight = bounds.maxY - SCREEN_MARGIN - gridTop
	local widestGap = math.max(DIVIDER_GAP, toolbarHeadingWidth + HEADING_GAP * 2)
	local availableWidth = bounds.maxX - bounds.minX - SCREEN_MARGIN * 2 - widestGap
	local columns = 1 + BARN_COLUMNS
	local unit = Constants.PIXEL_SCALE
	local size = math.min(
		Slot.SIZE,
		(availableHeight - (ROWS - 1) * SLOT_GAP) / ROWS,
		(availableWidth - (columns - 2) * SLOT_GAP) / columns
	)
	size = math.max(1, math.floor(size / unit)) * unit -- whole art px (ADR-0024)

	local dividerGap = math.ceil(math.max(DIVIDER_GAP, toolbarHeadingWidth - size + HEADING_GAP * 2) / unit) * unit
	local gridWidth = columns * size + (columns - 2) * SLOT_GAP + dividerGap
	local left = math.floor(((bounds.minX + bounds.maxX) / 2 - gridWidth / 2) / unit) * unit
	local columnX = { left }
	for column = 2, columns do
		columnX[column] = left + size + dividerGap + (column - 2) * (size + SLOT_GAP)
	end
	return { size = size, gridTop = gridTop, columnX = columnX, dividerGap = dividerGap }
end

-- Same size and spot as the barn button that opened the view.
local function drawCloseButton(root)
	local rect = Layout.getHudRect()
	local button = Slot.new(root, rect.minX, rect.minY, nil, rect.size, rect.pixel)
	Slot.drawPixelIcon(button, CLOSE_ICON_PATH, CLOSE_ICON_PIXELS,
		math.floor((Layout.HUD_PIXELS - CLOSE_ICON_PIXELS) / 2), rect.pixel)
	button.background:addEventListener("tap", function()
		BarnView.hide()
		return true
	end)
end

function BarnView.show()
	BarnView.hide()
	Selection.clear()

	local root = display.newGroup()
	current = { root = root }

	-- Opaque backdrop that swallows every touch and tap, hiding the garden.
	local backdrop = display.newRect(root,
		display.screenOriginX + display.actualContentWidth / 2,
		display.screenOriginY + display.actualContentHeight / 2,
		display.actualContentWidth, display.actualContentHeight)
	backdrop:setFillColor(Color.hexToRGB(BACKDROP_HEX))
	backdrop:addEventListener("touch", function()
		return true
	end)
	backdrop:addEventListener("tap", function()
		return true
	end)

	local bounds = safeRect()
	local headingHeight = Font.capHeight(Constants.FONT_SIZE_SMALL)
	local toolbarHeading = newText(root, "Toolbar", 0, 0)
	local layout = computeLayout(bounds, headingHeight, toolbarHeading.width)
	current.layout = layout

	-- The toolbar column sits on a tinted backing, with a divider before the barn.
	local columnHeight = ROWS * layout.size + (ROWS - 1) * SLOT_GAP
	Frame.new(root, layout.columnX[1] - TINT_PADDING, layout.gridTop - TINT_PADDING,
		layout.size + TINT_PADDING * 2, columnHeight + TINT_PADDING * 2, "backing")

	-- One art pixel wide, on the art-pixel grid.
	local unit = Constants.PIXEL_SCALE
	local dividerX = layout.columnX[1] + layout.size + math.floor(layout.dividerGap / unit / 2) * unit
	local dividerTop = layout.gridTop - HEADING_GAP - headingHeight
	local divider = display.newRect(root, dividerX, dividerTop, unit, layout.gridTop + columnHeight - dividerTop)
	divider.anchorX, divider.anchorY = 0, 0
	divider:setFillColor(Color.hexToRGB(INK_HEX))

	local headingY = layout.gridTop - HEADING_GAP - headingHeight
	toolbarHeading.x = layout.columnX[1] + layout.size / 2
	Font.placeCapsAt(toolbarHeading, headingY, Constants.FONT_SIZE_SMALL)
	local barnLeft, barnRight = layout.columnX[2], layout.columnX[1 + BARN_COLUMNS] + layout.size
	newText(root, "Barn", (barnLeft + barnRight) / 2, headingY)

	drawCloseButton(root)
	buildGrid()
end

Inventory.onChanged(function()
	if current then
		buildGrid()
	end
end)

return BarnView
