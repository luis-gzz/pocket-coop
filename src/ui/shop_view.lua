local Constants = require("src.util.constants")
local Color = require("src.util.color")
local Font = require("src.ui.font")
local Frame = require("src.ui.frame")
local Slot = require("src.ui.slot")
local Layout = require("src.ui.layout")
local Catalog = require("src.ui.catalog")
local Selection = require("src.ui.selection")
local DropZone = require("src.ui.drop_zone")
local Inventory = require("src.systems.inventory")
local Wallet = require("src.systems.wallet")
local Tuning = require("src.systems.tuning")
local Garden = require("src.systems.garden")

-- The shop (CONTEXT.md's Shop): a full-screen page opened from the HUD's
-- shop button, with a Buy tab (a grid of items by section; tapping one opens its popup)
-- and a Sell tab (eggs from the stash). The game keeps running behind it;
-- the HUD's counters stay drawn above it.
local ShopView = {}

-- Spatial constants are native * Constants.PIXEL_SCALE, like the rest of the UI.
local U = Constants.PIXEL_SCALE
local MARGIN = 6 * U
local GAP = 4 * U
local TAB_HEIGHT = 14 * U
local INACTIVE_TEXT_ALPHA = 0.6
local BUTTON_HEIGHT = 14 * U
local PANEL_PADDING = 4 * U
local COLUMN_GAP = 3 * U
local PRICE_GAP = 2 * U -- slot to its price
local PART_GAP = 2 * U -- between a label's words and its coin icon
local COUNT_WIDTH = 20 * U
local COIN_WIDTH, COIN_HEIGHT = 6, 7 -- art px
local ARROW_WIDTH, ARROW_HEIGHT = 5, 3 -- art px
local FONT_SIZE = Constants.FONT_SIZE_SMALL

local BACKDROP_HEX = "e5ceb4"
local INK_HEX = "3a3858"
local CREAM_HEX = "f2f0e5" -- a frame's fill
local PAGE_HEX = "d3a068" -- the backing frame's fill: the page panel and the active tab
local DISABLED_ALPHA = 0.4
local DIM_ALPHA = 0.4

local CLOSE_ICON_PATH = "assets/ui/close_icon.png"
local CLOSE_ICON_PIXELS = 7
local COIN_PATH = "assets/ui/coin_icon.png"

-- A move further than this scrolls the grid and never selects (as the toolbar's).
local TAP_SLOP = 10
local REPEAT_DELAY, REPEAT_TIME = 400, 80 -- ms: a held arrow repeats

-- Top to bottom: Food ends up nearest the tabs, and the thumb.
local SECTIONS = {
	{ key = "fixtures", title = "Fixtures" },
	{ key = "treats", title = "Treats" },
	{ key = "food", title = "Food" },
}

local COIN = {} -- marks a coin icon in a label's parts

local lastTab = "buy" -- this session's last-used tab
local scrollOffsets = { buy = 0, sell = 0 }
local current = nil
local shownListeners = {}

local itemsByType = {}
for _, item in ipairs(Catalog) do
	itemsByType[item.type] = item
end

-- listener(), after the page is shown.
function ShopView.onShown(listener)
	table.insert(shownListeners, listener)
end

local hiddenListeners = {}

-- listener(), after it closes.
function ShopView.onHidden(listener)
	table.insert(hiddenListeners, listener)
end

function ShopView.isOpen()
	return current ~= nil
end

local function stopRepeat()
	if current and current.repeatHandle then
		timer.cancel(current.repeatHandle)
		current.repeatHandle = nil
	end
end

function ShopView.hide()
	if not current then
		return
	end
	stopRepeat()
	current.root:removeSelf()
	current = nil
	for _, listener in ipairs(hiddenListeners) do
		listener()
	end
end

local function snap(value)
	return math.floor(value / U + 0.5) * U
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

local function swallow(object)
	object:addEventListener("touch", function()
		return true
	end)
	object:addEventListener("tap", function()
		return true
	end)
end

local function newText(parent, text, x, centerY, anchorX)
	local label = display.newText(parent, text, 0, 0, Constants.FONT, FONT_SIZE)
	label.anchorX = anchorX or 0.5
	label.x = x
	Font.centerCapsOn(label, centerY, FONT_SIZE)
	label:setFillColor(Color.hexToRGB(INK_HEX))
	return label
end

-- Words and coin icons in a row on centerY; align is "left", "center", or
-- "right" of x. Returns the group and its width.
local function newLabel(parent, parts, x, centerY, align)
	local group = display.newGroup()
	parent:insert(group)
	local cursor = 0
	for index, part in ipairs(parts) do
		if index > 1 then
			cursor = cursor + PART_GAP
		end
		if part == COIN then
			local icon = display.newImageRect(group, COIN_PATH, COIN_WIDTH * U, COIN_HEIGHT * U)
			icon.anchorX = 0
			icon.x, icon.y = cursor, snap(centerY - COIN_HEIGHT * U / 2) + COIN_HEIGHT * U / 2
			cursor = cursor + COIN_WIDTH * U
		else
			local text = newText(group, part, cursor, centerY, 0)
			cursor = cursor + text.width
		end
	end
	if align == "center" then
		group.x = snap(x - cursor / 2)
	elseif align == "right" then
		group.x = snap(x - cursor)
	else
		group.x = x
	end
	return group, cursor
end

-- A framed button with a label centered in it; greyed and inert unless enabled.
local function newButton(parent, x, y, width, parts, enabled, onTap)
	local group = display.newGroup()
	parent:insert(group)
	local label, labelWidth = newLabel(group, parts, 0, y + BUTTON_HEIGHT / 2, "left")
	local frame, snappedWidth = Frame.new(group, x, y, width, BUTTON_HEIGHT, enabled and "button" or "frame")
	frame:toBack()
	label.x = snap(x + snappedWidth / 2 - labelWidth / 2)
	group.alpha = enabled and 1 or DISABLED_ALPHA
	group:addEventListener("tap", function()
		if enabled then
			onTap()
		end
		return true
	end)
	return group
end

-- A square arrow button that steps once on touch, then repeats while held.
local function newArrow(parent, x, y, path, onStep)
	local button = Slot.new(parent, x, y, nil, BUTTON_HEIGHT)
	local icon = display.newImageRect(button, path, ARROW_WIDTH * U, ARROW_HEIGHT * U)
	icon.anchorX, icon.anchorY = 0, 0
	icon.x = snap((button.size - ARROW_WIDTH * U) / 2)
	icon.y = snap((button.size - ARROW_HEIGHT * U) / 2)
	local background = button.background
	background:addEventListener("touch", function(event)
		if event.phase == "began" then
			display.getCurrentStage():setFocus(background, event.id)
			background.isFocus = true
			stopRepeat()
			onStep()
			current.repeatHandle = timer.performWithDelay(REPEAT_DELAY, function()
				current.repeatHandle = timer.performWithDelay(REPEAT_TIME, onStep, 0)
			end)
		elseif background.isFocus and (event.phase == "ended" or event.phase == "cancelled") then
			display.getCurrentStage():setFocus(background, nil)
			background.isFocus = false
			stopRepeat()
		end
		return true
	end)
	background:addEventListener("tap", function()
		return true
	end)
	return button
end

-- Down arrow, the count, up arrow, left to right from x on row y. Returns
-- the setter for the count's text and the row's right edge.
local function newCountControl(parent, x, y, onDown, onUp)
	newArrow(parent, x, y, "assets/ui/arrow_down.png", onDown)
	local countX = x + BUTTON_HEIGHT + COUNT_WIDTH / 2
	newArrow(parent, x + BUTTON_HEIGHT + COUNT_WIDTH, y, "assets/ui/arrow_up.png", onUp)
	local text = nil
	local function setCount(n)
		if text then
			text:removeSelf()
		end
		text = newText(parent, tostring(n), countX, y + BUTTON_HEIGHT / 2)
	end
	return setCount, x + BUTTON_HEIGHT * 2 + COUNT_WIDTH
end

------------------------------------------------------------------ grid and popup

-- Both tabs are a grid of items, each opening a popup at the page's bottom.
-- The sell tab's items are egg kinds; just the one so far.
local SELL_ITEMS = {
	{
		type = "egg", name = "Egg", icon = "assets/fauna/egg_large.png", iconWidth = 11, iconHeight = 13,
		price = Tuning.EGG_PRICE, description = "A fresh egg from a happy hen.",
	},
}
for _, item in ipairs(SELL_ITEMS) do
	itemsByType[item.type] = item
end

local function affordable(item)
	return math.floor(Wallet.get() / item.price)
end

-- The current tab's grid: groups of items, each with an optional heading.
local function getGroups()
	if lastTab == "sell" then
		return { { items = SELL_ITEMS } }
	end
	local groups = {}
	for _, section in ipairs(SECTIONS) do
		local items = {}
		for _, item in ipairs(Catalog) do
			if item.price and item.section == section.key then
				table.insert(items, item)
			end
		end
		if #items > 0 then
			table.insert(groups, { title = section.title, items = items })
		end
	end
	return groups
end

-- What an item's popup offers on the current tab: its info line, the
-- count's range and starting value, and the action.
local function popupRules(item)
	if lastTab == "sell" then
		local have = Garden.getCollectedCount()
		return {
			info = "Have: " .. have, min = math.min(1, have), max = have, start = have, verb = "Sell",
			canAct = function(count)
				return count > 0
			end,
			act = function(count)
				Garden.sellEggs(count)
			end,
		}
	end
	local canAfford = affordable(item)
	return {
		info = "Own: " .. Garden.getOwned(item.type), min = 1, max = math.max(1, canAfford), start = 1, verb = "Buy",
		canAct = function()
			return canAfford >= 1
		end,
		act = function(count)
			if Wallet.spend(count * item.price) then
				DropZone.landed(Inventory.add(item.type, count))
			end
		end,
	}
end

-- An egg kind with none in the stash is greyed out, though still tappable.
local function refreshGreyed()
	for _, cell in pairs(current.cells or {}) do
		local greyed = lastTab == "sell" and Garden.getCollectedCount() == 0
		cell.slot.alpha = greyed and DISABLED_ALPHA or 1
		cell.price.alpha = cell.slot.alpha
	end
end

local openPopup -- defined below

local function buildGrid(page, area)
	local width, height = area.maxX - area.minX, area.maxY - area.minY
	local container = display.newContainer(page, width, height)
	container.x, container.y = (area.minX + area.maxX) / 2, (area.minY + area.maxY) / 2
	local content = display.newGroup()
	container:insert(content)

	-- Catches drags between slots, so the whole area scrolls.
	local catcher = display.newRect(content, 0, 0, width, height)
	catcher.anchorX, catcher.anchorY = 0, 0
	catcher.isVisible = false
	catcher.isHitTestable = true

	local columns = math.max(1, math.floor((width + COLUMN_GAP) / (Slot.SIZE + COLUMN_GAP)))
	local left = snap((width - (columns * Slot.SIZE + (columns - 1) * COLUMN_GAP)) / 2)
	local headingHeight = Font.capHeight(FONT_SIZE)
	local cellHeight = Slot.SIZE + PRICE_GAP + COIN_HEIGHT * U
	local cells = {}
	local y = 0
	for _, group in ipairs(getGroups()) do
		-- One art pixel tall, on the art-pixel grid. The first group's
		-- would double the line under the tabs.
		if y > 0 then
			local divider = display.newRect(content, left, y, width - left * 2, U)
			divider.anchorX, divider.anchorY = 0, 0
			divider:setFillColor(Color.hexToRGB(INK_HEX))
			y = y + U + GAP
		end
		if group.title then
			newText(content, group.title, left, y + headingHeight / 2, 0)
			y = y + headingHeight + GAP
		end
		for index, item in ipairs(group.items) do
			local column = (index - 1) % columns
			local row = math.floor((index - 1) / columns)
			local x = left + column * (Slot.SIZE + COLUMN_GAP)
			local cellY = y + row * (cellHeight + GAP)
			local slot = Slot.new(content, x, cellY, item)
			local price = newLabel(content, { COIN, tostring(item.price) }, x + Slot.SIZE / 2,
				cellY + Slot.SIZE + PRICE_GAP + COIN_HEIGHT * U / 2, "center")
			cells[item.type] = { slot = slot, price = price, item = item }
		end
		y = y + math.ceil(#group.items / columns) * (cellHeight + GAP)
	end
	-- Covers the whole visible area, wherever the content sits.
	catcher.height = math.max(height, y)
	catcher.y = y - catcher.height

	-- Bottom-justified: the content's last row sits on the area's bottom. An
	-- offset of 0 shows the bottom; dragging down scrolls up to the top.
	-- Each tab keeps its own scroll position this session.
	local maxScroll = math.max(0, y - height)
	local function scrollTo(offset)
		scrollOffsets[lastTab] = math.max(0, math.min(maxScroll, offset))
		content.x, content.y = -width / 2, height / 2 - y + scrollOffsets[lastTab]
	end
	scrollTo(scrollOffsets[lastTab])

	-- A touch within TAP_SLOP is a tap (onTap); one that moves further scrolls.
	local function addTouch(target, onTap)
		local startY, scrollStart, scrolling
		target:addEventListener("touch", function(event)
			if event.phase == "began" then
				display.getCurrentStage():setFocus(target, event.id)
				target.isFocus = true
				startY, scrollStart, scrolling = event.y, scrollOffsets[lastTab], false
			elseif target.isFocus then
				if event.phase == "moved" then
					local dx, dy = event.x - event.xStart, event.y - startY
					if not scrolling and dx * dx + dy * dy > TAP_SLOP * TAP_SLOP then
						scrolling = true
					end
					if scrolling then
						scrollTo(scrollStart + dy)
					end
				elseif event.phase == "ended" or event.phase == "cancelled" then
					display.getCurrentStage():setFocus(target, nil)
					target.isFocus = false
					if event.phase == "ended" and not scrolling and onTap then
						onTap()
					end
				end
			end
			return true
		end)
		target:addEventListener("tap", function()
			return true
		end)
	end

	addTouch(catcher, nil)
	for itemType, cell in pairs(cells) do
		addTouch(cell.slot.background, function()
			openPopup(itemType)
		end)
	end
	current.cells = cells
	refreshGreyed()
end

local buildCard -- defined below; rebuilt after each purchase

local function closePopup()
	stopRepeat()
	if current.popup then
		current.popup:removeSelf()
		current.popup, current.card = nil, nil
	end
	current.selectedType = nil
	for _, cell in pairs(current.cells or {}) do
		cell.slot.setSelected(false)
	end
end

-- The item popup over the buy grid (CONTEXT.md's Buy popup). A tap outside
-- the card closes it.
openPopup = function(itemType)
	closePopup()
	current.selectedType = itemType
	current.count = nil
	current.cells[itemType].slot.setSelected(true)

	local popup = display.newGroup()
	current.root:insert(popup)
	current.popup = popup
	local dim = display.newRect(popup,
		display.screenOriginX + display.actualContentWidth / 2,
		display.screenOriginY + display.actualContentHeight / 2,
		display.actualContentWidth, display.actualContentHeight)
	dim:setFillColor(Color.hexToRGB(INK_HEX))
	dim.alpha = DIM_ALPHA
	dim:addEventListener("touch", function()
		return true
	end)
	-- Listener attached a frame late (as in welcome_card.lua) so the tap
	-- that opened the popup doesn't close it.
	timer.performWithDelay(1, function()
		pcall(function()
			dim:addEventListener("tap", function()
				closePopup()
				return true
			end)
		end)
	end)
	buildCard()
end

buildCard = function()
	stopRepeat()
	if current.card then
		current.card:removeSelf()
	end
	local item = itemsByType[current.selectedType]
	local card = display.newGroup()
	current.popup:insert(card)
	current.card = card

	local panel = current.panel
	local width = panel.maxX - panel.minX

	-- Laid out from the card's top-left at (0, 0), then the card is set on
	-- the page panel's bottom edge, within a thumb's reach.
	local rules = popupRules(item)
	local x, y = PANEL_PADDING, PANEL_PADDING
	Slot.new(card, x, y, item) -- no count here: the info line says it
	local textX = x + Slot.SIZE + GAP
	local lineGap = (Slot.SIZE - Font.capHeight(FONT_SIZE) * 2) / 3
	local nameY = y + lineGap + Font.capHeight(FONT_SIZE) / 2
	newText(card, item.name, textX, nameY, 0)
	newLabel(card, { COIN, tostring(item.price) }, width - PANEL_PADDING, nameY, "right")
	newText(card, rules.info, textX, nameY + lineGap + Font.capHeight(FONT_SIZE), 0)
	y = y + Slot.SIZE + GAP

	local description = display.newText({
		parent = card, text = item.description or "", font = Constants.FONT, fontSize = FONT_SIZE,
		width = width - PANEL_PADDING * 2,
	})
	description.anchorX = 0
	description.x = x
	Font.placeCapsAt(description, y, FONT_SIZE)
	description:setFillColor(Color.hexToRGB(INK_HEX))
	y = y + Font.inkHeight(description, FONT_SIZE) + GAP

	current.count = math.max(rules.min, math.min(current.count or rules.start, rules.max))
	local rowY = y
	local actionButton = nil
	local setCount, controlRight
	local buttonX = nil
	local function refresh()
		setCount(current.count)
		if actionButton then
			actionButton:removeSelf()
		end
		local count = current.count
		actionButton = newButton(card, buttonX, rowY, width - PANEL_PADDING - buttonX,
			{ rules.verb .. " " .. count, COIN, tostring(count * item.price) }, rules.canAct(count), function()
				rules.act(count)
				-- Selling empties the count back to the (new) stash; buying keeps it.
				if lastTab == "sell" then
					current.count = nil
				end
				refreshGreyed()
				buildCard()
			end)
	end
	setCount, controlRight = newCountControl(card, x, rowY, function()
		current.count = math.max(rules.min, current.count - 1)
		refresh()
	end, function()
		current.count = math.min(rules.max, current.count + 1)
		refresh()
	end)
	buttonX = controlRight + GAP
	refresh()

	local frame, _, height = Frame.new(card, 0, 0, width, rowY + BUTTON_HEIGHT + PANEL_PADDING)
	frame:toBack()
	swallow(frame)
	card.x = panel.minX
	card.y = panel.maxY - height
end

------------------------------------------------------------------ page

local function buildPage()
	closePopup()
	if current.page then
		current.page:removeSelf()
	end
	current.cells = nil
	local page = display.newGroup()
	current.pageLayer:insert(page)
	current.page = page
	buildGrid(page, current.pageArea)
end

local buildTabs

local function selectTab(tab)
	if tab == lastTab then
		return
	end
	lastTab = tab
	buildTabs()
	buildPage()
end

-- Folder tabs under a framed page panel: each tab is half the page wide and
-- they share their middle outline. The inactive tab sits behind in cream,
-- its top edge the panel's bottom; the active one is darker tan like the
-- panel and its sides run straight up into the panel's.
buildTabs = function()
	if current.tabs then
		current.tabs:removeSelf()
		current.tabHits:removeSelf()
	end
	local tabs = display.newGroup()
	current.frameLayer:insert(tabs)
	current.tabs = tabs
	local hits = display.newGroup()
	current.chrome:insert(hits)
	current.tabHits = hits

	local panel = current.panel
	local y = current.tabTop
	local half = snap((panel.maxX - panel.minX + U) / 2)
	local buy = { key = "buy", title = "Buy", x = panel.minX }
	local sell = { key = "sell", title = "Sell", x = panel.minX + half - U }
	local active = lastTab == "buy" and buy or sell
	local inactive = lastTab == "buy" and sell or buy

	local _, inactiveWidth = Frame.new(tabs, inactive.x, y, half, TAB_HEIGHT, "frame")
	-- Taller than the tab, upward, so its upper corners hide under the panel.
	local _, activeWidth = Frame.new(tabs, active.x, y - GAP, half, TAB_HEIGHT + GAP, "backing")
	Frame.new(tabs, panel.minX, panel.minY, panel.maxX - panel.minX, panel.maxY - panel.minY, "backing")
	-- Opens the panel's bottom edge (and its corner pixel) over the active tab.
	local opening = display.newRect(tabs, active.x + U, panel.maxY - U * 2, activeWidth - U * 2, U * 2)
	opening.anchorX, opening.anchorY = 0, 0
	opening:setFillColor(Color.hexToRGB(PAGE_HEX))

	-- Squares the inactive tab's top corners where it meets the panel:
	-- the frames round them off, which leaves notches.
	local outerX = inactive == sell and panel.maxX - U or panel.minX
	local innerX = inactive == sell and outerX - U or outerX + U
	local function pixel(x, pixelY, height, hex)
		local rect = display.newRect(tabs, x, pixelY, U, height)
		rect.anchorX, rect.anchorY = 0, 0
		rect:setFillColor(Color.hexToRGB(hex))
	end
	pixel(outerX, panel.maxY - U * 2, U * 3, INK_HEX)
	pixel(innerX, panel.maxY - U * 2, U, PAGE_HEX)
	pixel(innerX, panel.maxY - U, U, INK_HEX)
	pixel(innerX, panel.maxY, U, CREAM_HEX)
	-- And its rounded inner corner, against the active tab's side.
	pixel(inactive == sell and sell.x + U or sell.x - U, panel.maxY, U, CREAM_HEX)

	for _, tab in ipairs({ active, inactive }) do
		local width = tab == active and activeWidth or inactiveWidth
		local label = newText(tabs, tab.title, tab.x + width / 2, y + TAB_HEIGHT / 2)
		label.alpha = tab == active and 1 or INACTIVE_TEXT_ALPHA
		-- Tap targets live above the page, which would otherwise block them.
		local hit = display.newRect(hits, tab.x, y, width, TAB_HEIGHT)
		hit.anchorX, hit.anchorY = 0, 0
		hit.isVisible = false
		hit.isHitTestable = true
		hit:addEventListener("tap", function()
			selectTab(tab.key)
			return true
		end)
	end
end

-- Same size and spot as the barn button, like the barn view's.
local function drawCloseButton(parent)
	local rect = Layout.getViewHudRect()
	local button = Slot.new(parent, rect.minX, rect.minY, nil, rect.size, rect.pixel)
	Slot.drawPixelIcon(button, CLOSE_ICON_PATH, CLOSE_ICON_PIXELS,
		math.floor((Layout.HUD_PIXELS - CLOSE_ICON_PIXELS) / 2), rect.pixel)
	button.background:addEventListener("tap", function()
		ShopView.hide()
		return true
	end)
end

function ShopView.show()
	ShopView.hide()
	Selection.clear()

	local root = display.newGroup()
	current = { root = root, selectedType = nil, count = nil }

	-- Opaque backdrop that swallows every touch and tap, hiding the garden.
	local backdrop = display.newRect(root,
		display.screenOriginX + display.actualContentWidth / 2,
		display.screenOriginY + display.actualContentHeight / 2,
		display.actualContentWidth, display.actualContentHeight)
	backdrop:setFillColor(Color.hexToRGB(BACKDROP_HEX))
	swallow(backdrop)

	current.frameLayer = display.newGroup()
	root:insert(current.frameLayer)
	current.pageLayer = display.newGroup()
	root:insert(current.pageLayer)
	current.chrome = display.newGroup()
	root:insert(current.chrome)

	local bounds = safeRect()
	local hudRect = Layout.getViewHudRect()
	current.bounds = bounds
	-- The HUD moves to the top in this view (ADR-0031); the tabs sit at the
	-- bottom, within a thumb's reach. The panel's bottom edge is the inactive tab's top edge.
	current.tabTop = snap(bounds.maxY - MARGIN - TAB_HEIGHT)
	current.panel = {
		minX = bounds.minX + MARGIN, maxX = bounds.maxX - MARGIN,
		minY = snap(hudRect.maxY + GAP), maxY = current.tabTop + U,
	}
	current.pageArea = {
		minX = current.panel.minX + PANEL_PADDING, maxX = current.panel.maxX - PANEL_PADDING,
		minY = current.panel.minY + PANEL_PADDING, maxY = current.panel.maxY - GAP,
	}

	-- Invisible, over the bands above and below the page, so a slot
	-- scrolled out of view can't be tapped.
	local screenTop = display.screenOriginY
	local screenBottom = screenTop + display.actualContentHeight
	for _, band in ipairs({ { screenTop, current.pageArea.minY }, { current.pageArea.maxY, screenBottom } }) do
		local blocker = display.newRect(current.chrome, display.screenOriginX, band[1],
			display.actualContentWidth, band[2] - band[1])
		blocker.anchorX, blocker.anchorY = 0, 0
		blocker.isVisible = false
		blocker.isHitTestable = true
		swallow(blocker)
	end

	drawCloseButton(current.chrome)
	buildTabs()
	buildPage()

	for _, listener in ipairs(shownListeners) do
		listener()
	end
end

return ShopView
