local Constants = require("src.util.constants")
local Color = require("src.util.color")
local Layout = require("src.ui.layout")

-- A small popover with a live-refreshed bar per row. Either anchored beside a
-- world point, or (content.corner) in a play area corner clear of it.
-- Only one can be open at a time.
local Tooltip = {}

-- All spatial constants below are native * Constants.PIXEL_SCALE, like every
-- other piece of art/UI in the project, so the tooltip scales along with the
-- rest of the game if PIXEL_SCALE ever changes instead of staying a fixed
-- absolute size.
local BAR_WIDTH = 50 * Constants.PIXEL_SCALE
local BAR_HEIGHT = 4 * Constants.PIXEL_SCALE
local ROW_HEIGHT = 14 * Constants.PIXEL_SCALE
local PANEL_PADDING = 5 * Constants.PIXEL_SCALE
local PANEL_PADDING_BOTTOM = 2.5 * Constants.PIXEL_SCALE
local PANEL_CORNER_RADIUS = 3 * Constants.PIXEL_SCALE
local PANEL_STROKE_WIDTH = 1 * Constants.PIXEL_SCALE
local TEXT_BAR_GAP = 2 * Constants.PIXEL_SCALE -- gap between a bar's label and the bar itself
local EDGE_MARGIN = 2 * Constants.PIXEL_SCALE -- keeps the panel off the very edge of the screen when clamped

local PANEL_FILL_HEX = "f2f0e5"
local PANEL_STROKE_HEX = "3a3858"
local BAR_FILL_HEX = "8ab060"

local ANCHOR_GAP = 10 * Constants.PIXEL_SCALE -- vertical gap kept between the anchor point and the panel
-- Half-height buffer approximating the anchor's on-screen size, used to
-- detect whether the panel (after edge-clamping) would cover it.
local ANCHOR_CLEARANCE = 8 * Constants.PIXEL_SCALE

-- Icon rows (row.icon) replace the text label with an icon left of the bar.
local ICON_SIZE = 8 * Constants.PIXEL_SCALE
local ICON_BAR_GAP = 3 * Constants.PIXEL_SCALE
local ICON_ROW_GAP = 2 * Constants.PIXEL_SCALE
local TITLE_GAP = 5 * Constants.PIXEL_SCALE -- between the title and the first row
-- Awkward.ttf reserves extra room above its ink; pull the title up to offset it.
local TITLE_TOP_TRIM = 3 * Constants.PIXEL_SCALE

local current = nil -- { dismiss, group, refresh, content }
local ignoringTap = false

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function makeBar(group, x, barY)
	local bg = display.newRect(group, x, barY, BAR_WIDTH, BAR_HEIGHT)
	bg.anchorX = 0
	bg:setFillColor(0.82, 0.82, 0.82)

	local fill = display.newRect(group, x, barY, BAR_WIDTH, BAR_HEIGHT)
	fill.anchorX = 0
	fill:setFillColor(Color.hexToRGB(BAR_FILL_HEX))

	return fill
end

local function makeLabeledBar(group, label, y)
	local text = display.newText(group, label, 0, y, Constants.FONT, Constants.FONT_SIZE_SMALL)
	text.anchorX = 0
	text.anchorY = 0
	text.x = 0
	text:setFillColor(0.2, 0.2, 0.2)

	return makeBar(group, 0, y + Constants.FONT_SIZE_SMALL + TEXT_BAR_GAP)
end

local function makeIconBar(group, iconPath, y)
	local icon = display.newImageRect(group, iconPath, ICON_SIZE, ICON_SIZE)
	icon.anchorX = 0
	icon.anchorY = 0
	icon.x = 0
	icon.y = y

	return makeBar(group, ICON_SIZE + ICON_BAR_GAP, y + ICON_SIZE / 2)
end

-- An icon followed by static text (a treat's payoff) instead of a bar.
-- Returns the row's width.
local function makeIconText(group, iconPath, text, y)
	local icon = display.newImageRect(group, iconPath, ICON_SIZE, ICON_SIZE)
	icon.anchorX = 0
	icon.anchorY = 0
	icon.x = 0
	icon.y = y

	local label = display.newText(
		group, text, ICON_SIZE + ICON_BAR_GAP, y + ICON_SIZE / 2, Constants.FONT, Constants.FONT_SIZE_SMALL
	)
	label.anchorX = 0
	label:setFillColor(0.2, 0.2, 0.2)
	return ICON_SIZE + ICON_BAR_GAP + label.width
end

-- Centered above the anchor, flipping below it if edge-clamping would cover it.
local function anchoredPosition(x, y, panelWidth, panelHeight)
	local minX = display.screenOriginX + EDGE_MARGIN
	local maxX = display.screenOriginX + display.actualContentWidth - panelWidth - EDGE_MARGIN
	local minY = display.screenOriginY + EDGE_MARGIN
	local maxY = display.screenOriginY + display.actualContentHeight - panelHeight - EDGE_MARGIN

	local panelX = clamp(x - panelWidth / 2, minX, maxX)
	local aboveY = clamp(y - panelHeight - ANCHOR_GAP, minY, maxY)
	local anchorTop = y - ANCHOR_CLEARANCE
	local anchorBottom = y + ANCHOR_CLEARANCE
	local wouldCoverAnchor = aboveY < anchorBottom and (aboveY + panelHeight) > anchorTop
	if wouldCoverAnchor then
		return panelX, clamp(y + ANCHOR_GAP, minY, maxY)
	end
	return panelX, aboveY
end

-- Bottom-right of the play area, or top-right if the anchor would sit under
-- the panel there. Picked once on open, never re-evaluated.
local function cornerPosition(x, y, panelWidth, panelHeight)
	local area = Layout.getPlayArea()
	local panelX = area.maxX - panelWidth - EDGE_MARGIN
	local bottomY = area.maxY - panelHeight - EDGE_MARGIN
	local overlapsX = x + ANCHOR_CLEARANCE > panelX and x - ANCHOR_CLEARANCE < panelX + panelWidth
	local overlapsY = y + ANCHOR_CLEARANCE > bottomY and y - ANCHOR_CLEARANCE < bottomY + panelHeight
	if overlapsX and overlapsY then
		return panelX, area.minY + EDGE_MARGIN
	end
	return panelX, bottomY
end

-- Shields the open tooltip from the tap Solar2D synthesizes for the touch
-- currently ending; cleared a frame later so genuine taps still dismiss.
function Tooltip.ignoreNextTap()
	ignoringTap = true
	timer.performWithDelay(1, function()
		ignoringTap = false
	end)
end

function Tooltip.hide()
	if not current then
		return
	end
	Runtime:removeEventListener("enterFrame", current.refresh)
	current.dismiss:removeSelf()
	current.group:removeSelf()
	if current.content.onHide then
		current.content.onHide()
	end
	current = nil
end

-- content: { x, y, rows, title?, corner?, onShow?, onHide? }, where each row is
-- { label | icon, getValue } or { icon, text } - see chicken.lua/lettuce.lua/
-- mealworm.lua for shape.
function Tooltip.show(content)
	Tooltip.hide()
	if content.onShow then
		content.onShow()
	end

	-- Full-screen, nearly-invisible tap target behind the panel, so tapping
	-- anywhere else dismisses the tooltip. Sized/centered directly (rather
	-- than positioned then re-anchored) since changing anchorX/Y after x/y
	-- is already set shifts the object instead of just relabeling it.
	local dismiss = display.newRect(
		display.screenOriginX + display.actualContentWidth / 2,
		display.screenOriginY + display.actualContentHeight / 2,
		display.actualContentWidth,
		display.actualContentHeight
	)
	dismiss:setFillColor(0, 0, 0, 0.01)
	-- The tap that opened this tooltip also generates Solar2D's own
	-- synthesized "tap" event, dispatched to whatever's on top - which would
	-- be this brand-new rect, instantly closing what we just opened. Attach
	-- the listener a frame late so it only catches later, genuine taps.
	timer.performWithDelay(1, function()
		pcall(function()
			dismiss:addEventListener("tap", function()
				if not ignoringTap then
					Tooltip.hide()
				end
				return true
			end)
		end)
	end)

	local rows = content.rows

	local group = display.newGroup()
	local contentGroup = display.newGroup()
	contentGroup.x = PANEL_PADDING

	local y = 0
	local title
	if content.title then
		title = display.newText(contentGroup, content.title, 0, 0, Constants.FONT, Constants.FONT_SIZE_LARGE)
		title:setFillColor(0.2, 0.2, 0.2)
		title.anchorX = 0
		title.anchorY = 0
		title.y = -TITLE_TOP_TRIM
		y = title.height - TITLE_TOP_TRIM + TITLE_GAP
	end

	local fills = {}
	local hasIcons = false
	local contentWidth = title and title.width or 0
	for index, row in ipairs(rows) do
		if row.text then
			hasIcons = true
			contentWidth = math.max(contentWidth, makeIconText(contentGroup, row.icon, row.text, y))
			y = y + ICON_SIZE + (index < #rows and ICON_ROW_GAP or 0)
		else
			local fill
			if row.icon then
				hasIcons = true
				fill = makeIconBar(contentGroup, row.icon, y)
				y = y + ICON_SIZE + (index < #rows and ICON_ROW_GAP or 0)
				contentWidth = math.max(contentWidth, ICON_SIZE + ICON_BAR_GAP + BAR_WIDTH)
			else
				fill = makeLabeledBar(contentGroup, row.label, y)
				y = y + ROW_HEIGHT
				contentWidth = math.max(contentWidth, BAR_WIDTH)
			end
			table.insert(fills, { fill = fill, getValue = row.getValue })
		end
	end

	local panelWidth = contentWidth + PANEL_PADDING * 2
	local panelHeight
	if hasIcons then
		contentGroup.y = PANEL_PADDING
		panelHeight = y + PANEL_PADDING * 2
	else
		-- Labeled rows carry their own space above the text and below the bar.
		panelHeight = y + PANEL_PADDING + PANEL_PADDING_BOTTOM
	end

	local place = content.corner and cornerPosition or anchoredPosition
	group.x, group.y = place(content.x, content.y, panelWidth, panelHeight)

	local panel = display.newRoundedRect(group, panelWidth / 2, panelHeight / 2, panelWidth, panelHeight, PANEL_CORNER_RADIUS)
	panel:setFillColor(Color.hexToRGB(PANEL_FILL_HEX))
	panel.strokeWidth = PANEL_STROKE_WIDTH
	panel:setStrokeColor(Color.hexToRGB(PANEL_STROKE_HEX))
	group:insert(contentGroup)

	local function refresh()
		for _, entry in ipairs(fills) do
			entry.fill.width = math.max(1, BAR_WIDTH * (entry.getValue() / 100))
		end
	end
	refresh()
	Runtime:addEventListener("enterFrame", refresh)

	current = { dismiss = dismiss, group = group, refresh = refresh, content = content }
end

return Tooltip
