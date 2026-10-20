local Constants = require("src.util.constants")
local Layout = require("src.ui.layout")
local Catalog = require("src.ui.catalog")
local Garden = require("src.systems.garden")
local Wiggle = require("src.util.wiggle")
local Color = require("src.util.color")

-- The bottom UI band's control for placing world objects (CONTEXT.md):
-- reads from ITEMS below instead of hardcoding the hen bed, so a future
-- item is one more definition, not new UI code.
local Toolbar = {}

local SLOT_MARGIN = 4 * Constants.PIXEL_SCALE
local SLOT_GAP = 3 * Constants.PIXEL_SCALE

-- Same visual language as tooltip.lua's panel (fill/stroke/corner radius),
-- duplicated here rather than shared - same convention as LONG_PRESS_TIME
-- below being its own copy instead of a shared module.
local SLOT_FILL_HEX = "f2f0e5"
local SLOT_STROKE_HEX = "3a3858"
local SLOT_CORNER_RADIUS = 3 * Constants.PIXEL_SCALE
local SLOT_STROKE_WIDTH = 1 * Constants.PIXEL_SCALE

-- Every item gets the same fixed-size square slot regardless of its own
-- icon's dimensions - the resting icon inside is scaled down to fit (see
-- wholeFit), decoupling toolbar row layout from any one item's art size.
-- The bottom band's height is derived from the play area's leftover space
-- (ADR-0009), not fixed, so this is sized to comfortably fit within it on
-- real devices rather than pinned a few units under a fixed band height.
local SLOT_SIZE = 19 * Constants.PIXEL_SCALE
local SLOT_PADDING = 2 * Constants.PIXEL_SCALE

-- ms; matches chicken.lua's/bed.lua's own long-press threshold - held here
-- as toolbar.lua's own copy rather than shared, same as their angle/timing.
local LONG_PRESS_TIME = 350
local WIGGLE_ANGLE = 8
local WIGGLE_STEP_TIME = 90

-- A horizontal move past this before the long press fires scrolls the
-- row instead of picking the item up.
local SCROLL_SLOP = 4 * Constants.PIXEL_SCALE

local ITEMS = Catalog

-- Fits an item's icon into a square box of availableSize at a whole number
-- of screen pixels per art pixel, never above world size (ADR-0020). Native
-- size is iconWidth/Height if given, else the world size over PIXEL_SCALE.
local function wholeFit(item, availableSize)
	local nativeWidth = item.iconWidth or math.floor(item.width / Constants.PIXEL_SCALE + 0.5)
	local nativeHeight = item.iconHeight or math.floor(item.height / Constants.PIXEL_SCALE + 0.5)
	local ppa = math.min(
		Constants.WORLD_PPA,
		Constants.snapPpa(availableSize * Constants.DEVICE_SCALE, math.max(nativeWidth, nativeHeight))
	)
	local unit = ppa / Constants.DEVICE_SCALE
	return nativeWidth * unit, nativeHeight * unit
end

function Toolbar.create()
	local band = Layout.getBottomBandRect()
	local centerY = (band.minY + band.maxY) / 2

	-- Slots live in a strip clipped to the band; a row wider than the band
	-- scrolls sideways. Strip coordinates match content coordinates at rest.
	local container = display.newContainer(band.maxX - band.minX, band.maxY - band.minY)
	container.x = (band.minX + band.maxX) / 2
	container.y = centerY
	local strip = display.newGroup()
	container:insert(strip)
	strip.x, strip.y = -container.x, -container.y

	local scrollOffset = 0
	local maxScroll = math.max(
		0, SLOT_MARGIN * 2 + #ITEMS * SLOT_SIZE + (#ITEMS - 1) * SLOT_GAP - (band.maxX - band.minX)
	)
	local function scrollTo(offset)
		scrollOffset = math.max(-maxScroll, math.min(0, offset))
		strip.x = -container.x + scrollOffset
	end

	local buttonX = band.minX + SLOT_MARGIN
	for _, item in ipairs(ITEMS) do
		local slotGroup = display.newGroup()
		strip:insert(slotGroup)
		slotGroup.x = buttonX
		slotGroup.y = centerY - SLOT_SIZE / 2

		local background = display.newRoundedRect(
			slotGroup, SLOT_SIZE / 2, SLOT_SIZE / 2, SLOT_SIZE, SLOT_SIZE, SLOT_CORNER_RADIUS
		)
		background:setFillColor(Color.hexToRGB(SLOT_FILL_HEX))
		background.strokeWidth = SLOT_STROKE_WIDTH
		background:setStrokeColor(Color.hexToRGB(SLOT_STROKE_HEX))

		-- Resting icon: whole-pixel fit within the slot's padded content box, a
		-- smaller "button" rendering decoupled from the item's actual
		-- in-world footprint. The dragged ghost below stays at full
		-- item.width/height so the player can judge true placement fit.
		local contentSize = SLOT_SIZE - SLOT_PADDING * 2
		local restWidth, restHeight = wholeFit(item, contentSize)
		local icon = display.newImageRect(slotGroup, item.icon, restWidth, restHeight)
		icon.x = SLOT_SIZE / 2
		icon.y = SLOT_SIZE / 2

		-- Hold-and-drag, mirroring chicken.lua's/bed.lua's long-press shape: a
		-- ghost only appears (and starts wiggling) once the hold clears
		-- LONG_PRESS_TIME, then follows the touch - at that same moment the
		-- slot's resting icon hides, leaving the slot visibly empty until the
		-- touch ends. A release where Garden.tryPlace succeeds places the
		-- item - anywhere else (a position that wouldn't fit fully in the
		-- play area, another band, a safe-area margin, or a release before
		-- the long-press even fires) cancels with nothing placed, but the
		-- icon always reappears either way.
		local ghost = nil
		local wiggleHandle = nil
		local pendingTouch = false
		local longPressHandle = nil
		local scrolling = false
		local touchStartX, scrollStartOffset

		local function beginDrag(startX, startY)
			icon.isVisible = false
			ghost = display.newImageRect(item.ghost or item.icon, item.width, item.height)
			ghost.alpha = 0.7
			ghost.x = startX
			ghost.y = startY
			wiggleHandle = Wiggle.start(ghost, WIGGLE_ANGLE, WIGGLE_STEP_TIME, function()
				return ghost ~= nil
			end)
		end

		local function onTouch(event)
			if event.phase == "began" then
				display.getCurrentStage():setFocus(background, event.id)
				background.isFocus = true
				pendingTouch = true
				touchStartX, scrollStartOffset = event.x, scrollOffset
				local startX, startY = event.x, event.y
				longPressHandle = timer.performWithDelay(LONG_PRESS_TIME, function()
					longPressHandle = nil
					if pendingTouch then
						beginDrag(startX, startY)
						pendingTouch = false
					end
				end)
			elseif background.isFocus then
				if event.phase == "moved" then
					if ghost then
						ghost.x = event.x
						ghost.y = event.y
					elseif pendingTouch and maxScroll > 0 and math.abs(event.x - touchStartX) > SCROLL_SLOP then
						if longPressHandle then
							timer.cancel(longPressHandle)
							longPressHandle = nil
						end
						pendingTouch = false
						scrolling = true
					end
					if scrolling then
						scrollTo(scrollStartOffset + event.x - touchStartX)
					end
				elseif event.phase == "ended" or event.phase == "cancelled" then
					display.getCurrentStage():setFocus(background, nil)
					background.isFocus = false

					if longPressHandle then
						timer.cancel(longPressHandle)
						longPressHandle = nil
					end
					pendingTouch = false
					scrolling = false

					if ghost then
						Wiggle.stop(wiggleHandle)
						wiggleHandle = nil
						if event.phase == "ended" then
							Garden.tryPlace(item.type, event.x, event.y)
						end
						ghost:removeSelf()
						ghost = nil
					end
					icon.isVisible = true
				end
			end
			return true
		end
		background:addEventListener("touch", onTouch)

		buttonX = buttonX + SLOT_SIZE + SLOT_GAP
	end
end

return Toolbar
