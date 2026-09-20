local Constants = require("src.constants")
local Color = require("src.color")

-- A small popover anchored to a world point: a labeled, live-refreshed bar
-- per row, plus an optional active-buff icon row. Only one can be open at a time.
local Tooltip = {}

-- All spatial constants below are native * Constants.PIXEL_SCALE, like every
-- other piece of art/UI in the project, so the tooltip scales along with the
-- rest of the game if PIXEL_SCALE ever changes instead of staying a fixed
-- absolute size.
local BAR_WIDTH = 50 * Constants.PIXEL_SCALE
local BAR_HEIGHT = 4 * Constants.PIXEL_SCALE
local ROW_HEIGHT = 14 * Constants.PIXEL_SCALE
local PANEL_PADDING = 5 * Constants.PIXEL_SCALE
local PANEL_PADDING_TOP = 10 * Constants.PIXEL_SCALE
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

-- Active-buff icon row, shown left-justified when content.buffs is given;
-- only currently-active buffs are drawn.
local BUFF_ICON_MARGIN_TOP = 3.5 * Constants.PIXEL_SCALE
local BUFF_ICON_GAP = 2 * Constants.PIXEL_SCALE

local current = nil -- { dismiss, group, refresh, content }

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function makeBar(group, label, y)
	local text = display.newText(group, label, 0, y, Constants.FONT, Constants.FONT_SIZE_SMALL)
	text.anchorX = 0
	text.anchorY = 0
	text.x = 0
	text:setFillColor(0.2, 0.2, 0.2)

	local barY = y + Constants.FONT_SIZE_SMALL + TEXT_BAR_GAP

	local bg = display.newRect(group, 0, barY, BAR_WIDTH, BAR_HEIGHT)
	bg.anchorX = 0
	bg:setFillColor(0.82, 0.82, 0.82)

	local fill = display.newRect(group, 0, barY, BAR_WIDTH, BAR_HEIGHT)
	fill.anchorX = 0
	fill:setFillColor(Color.hexToRGB(BAR_FILL_HEX))

	return fill
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

-- content: { x, y, rows, buffs?, onShow?, onHide? } - see chicken.lua/feed.lua for shape.
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
				Tooltip.hide()
				return true
			end)
		end)
	end)

	local rows = content.rows
	local buffs = content.buffs or {}

	local function anyBuffActive()
		for _, buff in ipairs(buffs) do
			if buff.isActive() then
				return true
			end
		end
		return false
	end

	-- No active buff means no reserved top strip at all.
	local topPadding = anyBuffActive() and PANEL_PADDING_TOP or 0

	local panelWidth = BAR_WIDTH + PANEL_PADDING * 2
	local panelHeight = ROW_HEIGHT * #rows + topPadding + PANEL_PADDING + PANEL_PADDING_BOTTOM

	local group = display.newGroup()

	-- Prefer centering above the anchor, clamped on all sides so the panel
	-- always stays fully on screen.
	local minX = display.screenOriginX + EDGE_MARGIN
	local maxX = display.screenOriginX + display.actualContentWidth - panelWidth - EDGE_MARGIN
	group.x = clamp(content.x - panelWidth / 2, minX, maxX)

	local minY = display.screenOriginY + EDGE_MARGIN
	local maxY = display.screenOriginY + display.actualContentHeight - panelHeight - EDGE_MARGIN

	local aboveY = clamp(content.y - panelHeight - ANCHOR_GAP, minY, maxY)
	-- If clamping would push the panel down far enough to cover the anchor,
	-- flip to below it instead.
	local anchorTop = content.y - ANCHOR_CLEARANCE
	local anchorBottom = content.y + ANCHOR_CLEARANCE
	local wouldCoverAnchor = aboveY < anchorBottom and (aboveY + panelHeight) > anchorTop
	if wouldCoverAnchor then
		group.y = clamp(content.y + ANCHOR_GAP, minY, maxY)
	else
		group.y = aboveY
	end

	local panel = display.newRoundedRect(group, panelWidth / 2, panelHeight / 2, panelWidth, panelHeight, PANEL_CORNER_RADIUS)
	panel:setFillColor(Color.hexToRGB(PANEL_FILL_HEX))
	panel.strokeWidth = PANEL_STROKE_WIDTH
	panel:setStrokeColor(Color.hexToRGB(PANEL_STROKE_HEX))

	-- Left-justified in the top padding strip, above the gauge rows. Each
	-- icon starts hidden; refresh() below shows only the active ones.
	local buffIcons = {}
	local buffX = PANEL_PADDING
	for _, buff in ipairs(buffs) do
		local icon = display.newImageRect(group, buff.icon, buff.size, buff.size)
		icon.anchorX = 0
		icon.anchorY = 0
		icon.x = buffX
		icon.y = BUFF_ICON_MARGIN_TOP
		icon.isVisible = false
		table.insert(buffIcons, { view = icon, def = buff })
		buffX = buffX + buff.size + BUFF_ICON_GAP
	end

	local contentGroup = display.newGroup()
	group:insert(contentGroup)
	contentGroup.x = PANEL_PADDING
	contentGroup.y = topPadding

	local fills = {}
	for index, row in ipairs(rows) do
		local fill = makeBar(contentGroup, row.label, (index - 1) * ROW_HEIGHT)
		table.insert(fills, { fill = fill, getValue = row.getValue })
	end

	local function refresh()
		for _, entry in ipairs(fills) do
			entry.fill.width = math.max(1, BAR_WIDTH * (entry.getValue() / 100))
		end
		for _, entry in ipairs(buffIcons) do
			entry.view.isVisible = entry.def.isActive()
		end
	end
	refresh()
	Runtime:addEventListener("enterFrame", refresh)

	current = { dismiss = dismiss, group = group, refresh = refresh, content = content }
end

return Tooltip
