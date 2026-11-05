local Constants = require("src.util.constants")
local Layout = require("src.ui.layout")
local Catalog = require("src.ui.catalog")
local Inventory = require("src.systems.inventory")
local Selection = require("src.ui.selection")
local DropZone = require("src.ui.drop_zone")
local Slot = require("src.ui.slot")
local Color = require("src.util.color")

-- The bottom UI band's row of item slots (CONTEXT.md's Toolbar): tap one to
-- select its item, then tap the world to use it (ADR-0022). Always shows
-- every toolbar slot, empty ones too, and reads Inventory for what's in them.
local Toolbar = {}

local SLOT_MARGIN = 4 * Constants.PIXEL_SCALE
local SLOT_GAP = 3 * Constants.PIXEL_SCALE

-- Content points (config.lua's 384-wide content ~ device points). A touch
-- moving further than this scrolls the row and never selects.
local TAP_SLOP = 10

-- Shown over the band while a fixture dragged off the map hovers it.
local HOVER_HEX = "4b80ca"
local HOVER_ALPHA = 0.3

local itemsByType = {}
for _, item in ipairs(Catalog) do
	itemsByType[item.type] = item
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

	local hover = display.newRect(container, 0, 0, bandWidth, band.maxY - band.minY)
	hover:setFillColor(Color.hexToRGB(HOVER_HEX))
	hover.alpha = HOVER_ALPHA
	hover.isVisible = false
	DropZone.onHover(function(isHovering)
		hover.isVisible = isHovering
	end)

	local strip = nil
	local slots = {} -- [index] = slot group

	local scrollOffset = 0
	local maxScroll = math.max(0, SLOT_MARGIN * 2 + Inventory.TOOLBAR_SLOTS * Slot.SIZE
		+ (Inventory.TOOLBAR_SLOTS - 1) * SLOT_GAP - bandWidth)

	local function scrollTo(offset)
		scrollOffset = math.max(-maxScroll, math.min(0, offset))
		strip.x = -container.x + scrollOffset
	end

	local function refreshSelection()
		local selected = Selection.get()
		for index, slot in ipairs(slots) do
			slot.setSelected(selected ~= nil and Inventory.get("toolbar", index) == selected)
		end
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

	local function slotX(index)
		return band.minX + SLOT_MARGIN + (index - 1) * (Slot.SIZE + SLOT_GAP)
	end

	local function build()
		if strip then
			strip:removeSelf()
		end
		strip = display.newGroup()
		container:insert(strip)
		strip.y = -container.y
		slots = {}

		for index = 1, Inventory.TOOLBAR_SLOTS do
			local itemType = Inventory.get("toolbar", index)
			local slot = Slot.new(strip, slotX(index), centerY - Slot.SIZE / 2, itemsByType[itemType])
			slots[index] = slot
			-- An empty slot deselects, the same as tapping the selected one.
			addTouch(slot.background, function()
				Selection.set(itemType ~= Selection.get() and itemType or nil)
			end)
		end

		scrollTo(scrollOffset)
		refreshSelection()
	end

	-- Scrolls a landed slot into view, then flashes it.
	DropZone.onLanded(function(area, index)
		if area ~= "toolbar" then
			return
		end
		local left = slotX(index) - band.minX - SLOT_MARGIN
		local right = left + Slot.SIZE + SLOT_MARGIN * 2
		if left + scrollOffset < 0 then
			scrollTo(-left)
		elseif right + scrollOffset > bandWidth then
			scrollTo(bandWidth - right)
		end
		slots[index].flash()
	end)

	build()
	Inventory.onChanged(build)
	Selection.onChanged(refreshSelection)
end

return Toolbar
