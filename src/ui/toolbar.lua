local Constants = require("src.util.constants")
local Layout = require("src.ui.layout")
local Catalog = require("src.ui.catalog")
local Inventory = require("src.systems.inventory")
local Selection = require("src.ui.selection")
local Slot = require("src.ui.slot")
local BarnPanel = require("src.ui.barn_panel")
local Font = require("src.ui.font")
local Color = require("src.util.color")

-- The bottom UI band's row of item slots (CONTEXT.md's Toolbar): tap one to
-- select its item, then tap the world to use it (ADR-0022). The barn slot
-- is always last. Reads Inventory's toolbar list, so it holds no item logic.
local Toolbar = {}

local SLOT_MARGIN = 4 * Constants.PIXEL_SCALE
local SLOT_GAP = 3 * Constants.PIXEL_SCALE

-- Content points (config.lua's 384-wide content ~ device points). A touch
-- moving further than this scrolls the row and never selects.
local TAP_SLOP = 10

local STROKE_HEX = "3a3858"
local BUTTON_FILL_HEX = "8ab060"
-- Same width as a slot; the label shrinks to fit it.
local STORE_WIDTH = Slot.SIZE
local STORE_HEIGHT = 9 * Constants.PIXEL_SCALE
local STORE_FONT_SIZE = 6 * Constants.PIXEL_SCALE
local STORE_LABEL_PADDING = 1 * Constants.PIXEL_SCALE
local STORE_GAP = 2 * Constants.PIXEL_SCALE
local BUTTON_CORNER_RADIUS = 2 * Constants.PIXEL_SCALE
local STROKE_WIDTH = 1 * Constants.PIXEL_SCALE

local itemsByType = {}
for _, item in ipairs(Catalog) do
	itemsByType[item.type] = item
end

-- Placeholder barn art (a red barn front) until a real icon exists.
local function drawBarnIcon(group)
	local unit = Constants.PIXEL_SCALE
	local cx, cy = Slot.SIZE / 2, Slot.SIZE / 2
	local roof = display.newPolygon(group, cx, cy - 3 * unit, { -6 * unit, 2 * unit, 0, -3 * unit, 6 * unit, 2 * unit })
	roof:setFillColor(Color.hexToRGB(STROKE_HEX))
	local body = display.newRect(group, cx, cy + 2.5 * unit, 10 * unit, 8 * unit)
	body:setFillColor(Color.hexToRGB("b45252"))
	local door = display.newRect(group, cx, cy + 4 * unit, 4 * unit, 5 * unit)
	door:setFillColor(Color.hexToRGB("f2f0e5"))
end

function Toolbar.create()
	local band = Layout.getBottomBandRect()
	local bandWidth = band.maxX - band.minX
	local centerY = (band.minY + band.maxY) / 2

	-- Slots live in a strip clipped to the band; a row wider than the band
	-- scrolls sideways. Strip coordinates match content coordinates at rest.
	local container = display.newContainer(bandWidth, band.maxY - band.minY)
	container.x = (band.minX + band.maxX) / 2
	container.y = centerY
	local strip = nil
	local slots = {} -- { [itemType] = slot group }

	local scrollOffset = 0
	local maxScroll = 0

	-- The Store button sits above the selected slot, outside the clipping
	-- container, and follows it as the row scrolls.
	local store = display.newGroup()
	local storeButton = display.newRoundedRect(store, 0, 0, STORE_WIDTH, STORE_HEIGHT, BUTTON_CORNER_RADIUS)
	storeButton:setFillColor(Color.hexToRGB(BUTTON_FILL_HEX))
	storeButton.strokeWidth = STROKE_WIDTH
	storeButton:setStrokeColor(Color.hexToRGB(STROKE_HEX))
	local storeFontSize = STORE_FONT_SIZE
	local storeLabel = display.newText(store, "Store", 0, 0, Constants.FONT, storeFontSize)
	local maxLabelWidth = STORE_WIDTH - STORE_LABEL_PADDING * 2
	if storeLabel.width > maxLabelWidth then
		storeFontSize = storeFontSize * maxLabelWidth / storeLabel.width
		storeLabel.size = storeFontSize
	end
	Font.centerCapsOn(storeLabel, 0, storeFontSize)
	storeLabel:setFillColor(0.2, 0.2, 0.2)
	store.y = band.minY - STORE_GAP - STORE_HEIGHT / 2
	store.isVisible = false
	-- Swallows touches too, so nothing in the world beneath starts a drag.
	storeButton:addEventListener("touch", function()
		return true
	end)
	storeButton:addEventListener("tap", function()
		local itemType = Selection.get()
		if itemType then
			Selection.clear()
			Inventory.store(itemType)
		end
		return true
	end)

	local function refreshStore()
		local slot = slots[Selection.get() or ""]
		if not slot then
			store.isVisible = false
			return
		end
		local x = slot:localToContent(Slot.SIZE / 2, 0)
		store.x = x
		store.isVisible = x >= band.minX and x <= band.maxX
	end

	local function scrollTo(offset)
		scrollOffset = math.max(-maxScroll, math.min(0, offset))
		strip.x = -container.x + scrollOffset
		refreshStore()
	end

	local function refreshSelection()
		local selected = Selection.get()
		for itemType, slot in pairs(slots) do
			slot.setSelected(itemType == selected)
		end
		refreshStore()
	end

	-- A touch that stays within TAP_SLOP is a tap (onTap); one that moves
	-- further scrolls the row instead.
	local function addTouch(background, onTap)
		local startX, startY, scrollStart, scrolling
		background:addEventListener("touch", function(event)
			if event.phase == "began" then
				display.getCurrentStage():setFocus(background, event.id)
				background.isFocus = true
				startX, startY, scrollStart, scrolling = event.x, event.y, scrollOffset, false
			elseif background.isFocus then
				if event.phase == "moved" then
					local dx, dy = event.x - startX, event.y - startY
					if not scrolling and dx * dx + dy * dy > TAP_SLOP * TAP_SLOP then
						scrolling = true
					end
					if scrolling then
						scrollTo(scrollStart + dx)
					end
				elseif event.phase == "ended" or event.phase == "cancelled" then
					display.getCurrentStage():setFocus(background, nil)
					background.isFocus = false
					if event.phase == "ended" and not scrolling then
						onTap()
					end
				end
			end
			return true
		end)
	end

	local function build()
		if strip then
			strip:removeSelf()
		end
		strip = display.newGroup()
		container:insert(strip)
		strip.y = -container.y
		slots = {}

		local types = Inventory.getToolbar()
		local slotY = centerY - Slot.SIZE / 2
		local x = band.minX + SLOT_MARGIN
		for _, itemType in ipairs(types) do
			local slot = Slot.new(strip, x, slotY, itemsByType[itemType])
			slots[itemType] = slot
			addTouch(slot.background, function()
				Selection.set(Selection.get() ~= itemType and itemType or nil)
			end)
			x = x + Slot.SIZE + SLOT_GAP
		end

		local barnSlot = Slot.new(strip, x, slotY)
		drawBarnIcon(barnSlot)
		addTouch(barnSlot.background, BarnPanel.toggle)

		local slotCount = #types + 1
		maxScroll = math.max(0, SLOT_MARGIN * 2 + slotCount * Slot.SIZE + (slotCount - 1) * SLOT_GAP - bandWidth)
		scrollTo(scrollOffset)
		refreshSelection()
	end

	build()
	Inventory.onChanged(build)
	Selection.onChanged(refreshSelection)
end

return Toolbar
