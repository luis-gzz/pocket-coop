local Constants = require("src.constants")
local Color = require("src.color")

-- A small popover anchored to a tapped chicken: three live gauge bars.
-- Petting happens on the tap that opens this (see Chicken:pet), not from a
-- button here. Only one can be open at a time.
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

local CHICKEN_GAP = 10 * Constants.PIXEL_SCALE -- vertical gap kept between the chicken and the panel
-- Half-height buffer approximating the chicken's on-screen size, used to
-- detect whether the panel (after edge-clamping) would cover the chicken.
local CHICKEN_CLEARANCE = 8 * Constants.PIXEL_SCALE

-- Active-buff icon row, shown left-justified in the panel's top padding
-- strip. Each entry is an icon + an isActive(gauges) predicate, so only
-- currently-active buffs are drawn. Pet is the only buff today; adding
-- another later is just appending another entry here.
local BUFF_ICON_MARGIN_TOP = 3.5 * Constants.PIXEL_SCALE
local BUFF_ICON_GAP = 2 * Constants.PIXEL_SCALE
local BUFFS = {
	{
		icon = "assets/fauna/heart.png",
		size = 9 * Constants.PIXEL_SCALE,
		isActive = function(gauges)
			return gauges:isPetBuffActive()
		end,
	},
}

local current = nil -- { dismiss, group, refresh, chicken }

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
	current.chicken:setSelected(false)
	current = nil
end

function Tooltip.show(chicken)
	Tooltip.hide()
	chicken:setSelected(true)

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

	local panelWidth = BAR_WIDTH + PANEL_PADDING * 2
	local panelHeight = ROW_HEIGHT * 3 + PANEL_PADDING_TOP + PANEL_PADDING + PANEL_PADDING_BOTTOM

	local group = display.newGroup()

	-- Prefer centering over / floating above the chicken, but clamp on all
	-- four sides so the panel always renders fully within the visible
	-- screen even when the chicken is near an edge or corner.
	local minX = display.screenOriginX + EDGE_MARGIN
	local maxX = display.screenOriginX + display.actualContentWidth - panelWidth - EDGE_MARGIN
	group.x = clamp(chicken.view.x - panelWidth / 2, minX, maxX)

	local minY = display.screenOriginY + EDGE_MARGIN
	local maxY = display.screenOriginY + display.actualContentHeight - panelHeight - EDGE_MARGIN

	local aboveY = clamp(chicken.view.y - panelHeight - CHICKEN_GAP, minY, maxY)
	-- Edge-clamping (e.g. the chicken is right at the top of the screen) can
	-- push the "above" position down far enough that the chicken ends up
	-- inside the panel's own vertical span. When that would happen, flip to
	-- below the chicken instead so the panel never covers it.
	local chickenTop = chicken.view.y - CHICKEN_CLEARANCE
	local chickenBottom = chicken.view.y + CHICKEN_CLEARANCE
	local wouldCoverChicken = aboveY < chickenBottom and (aboveY + panelHeight) > chickenTop
	if wouldCoverChicken then
		group.y = clamp(chicken.view.y + CHICKEN_GAP, minY, maxY)
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
	for _, buff in ipairs(BUFFS) do
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
	contentGroup.y = PANEL_PADDING_TOP

	local satietyFill = makeBar(contentGroup, "Fullness", 0)
	local cleanlinessFill = makeBar(contentGroup, "Cleanliness", ROW_HEIGHT)
	local happinessFill = makeBar(contentGroup, "Happiness", ROW_HEIGHT * 2)

	local function refresh()
		local gauges = chicken.gauges
		satietyFill.width = math.max(1, BAR_WIDTH * (gauges.satiety / 100))
		cleanlinessFill.width = math.max(1, BAR_WIDTH * (gauges.cleanliness / 100))
		happinessFill.width = math.max(1, BAR_WIDTH * (gauges:getHappiness() / 100))
		for _, entry in ipairs(buffIcons) do
			entry.view.isVisible = entry.def.isActive(gauges)
		end
	end
	refresh()
	Runtime:addEventListener("enterFrame", refresh)

	current = { dismiss = dismiss, group = group, refresh = refresh, chicken = chicken }
end

return Tooltip
