local Constants = require("src.util.constants")
local Layout = require("src.ui.layout")
local Font = require("src.ui.font")
local Garden = require("src.systems.garden")
local Wallet = require("src.systems.wallet")
local Slot = require("src.ui.slot")
local Frame = require("src.ui.frame")
local BarnView = require("src.ui.barn_view")
local ShopView = require("src.ui.shop_view")
local DropZone = require("src.ui.drop_zone")

-- The HUD band, between the garden and the toolbar (ADR-0031), packed
-- right, left to right: the coin counter, the egg counter (the
-- player's stash, not the eggs sitting uncollected in the world - see
-- CONTEXT.md), the shop button, and the barn button. The counters stay
-- drawn above the shop page.
local Hud = {}

-- All in HUD art px (Layout.getHudRect's pixel), world-sized (ADR-0025).
local ICON_TEXT_GAP = 3
local BUTTON_GAP = 3
local FRAME_PADDING = 3 -- inside a counter's frame, each end
local BUTTON_ICON_PIXELS = 9
local FONT_PIXELS = 11

local EGG_ICON = { path = "assets/fauna/ChickenEgg.png", width = 6, height = 7 }
local COIN_ICON = { path = "assets/ui/coin_icon.png", width = 6, height = 7 }
local BARN_ICON_PATH = "assets/objects/barn_icon_small.png"
local SHOP_ICON_PATH = "assets/objects/shop_icon_small.png"

local function newButton(parent, x, rect, iconPath, onTap)
	local button = Slot.new(parent, x, rect.minY, nil, rect.size, rect.pixel)
	Slot.drawPixelIcon(button, iconPath, BUTTON_ICON_PIXELS,
		(Layout.HUD_PIXELS - BUTTON_ICON_PIXELS) / 2, rect.pixel)
	button.background:addEventListener("tap", function()
		onTap()
		return true
	end)
	return button
end

-- A framed icon and number, as tall as the HUD buttons, widening leftward
-- from its right edge as the number gains digits. update(value, right)
-- redraws it if anything changed and returns its left edge.
local function newCounter(parent, rect, icon)
	local pixel = rect.pixel
	local centerY = (rect.minY + rect.maxY) / 2
	local fontSize = FONT_PIXELS * pixel
	local group = display.newGroup()
	parent:insert(group)
	local frame = nil
	local shownValue, shownRight, left = nil, nil, nil

	local image = display.newImageRect(group, icon.path, icon.width * pixel, icon.height * pixel)
	image.anchorX = 0
	-- The icons have no transparent padding, so their center is their visual center.
	image.anchorY = 0.5
	image.y = centerY

	-- No explicit width/height here: constraining newText's box height to
	-- the icon's (much shorter than the font's line height) clipped the glyph.
	local text = display.newText({ text = "0", x = 0, y = 0, font = Constants.FONT, fontSize = fontSize })
	group:insert(text)
	text.anchorX = 1
	Font.centerCapsOn(text, centerY, fontSize)
	text:setFillColor(0.2, 0.2, 0.2)

	return function(value, right)
		if value == shownValue and right == shownRight then
			return left
		end
		shownValue, shownRight = value, right
		text.text = tostring(value)
		text.x = right - FRAME_PADDING * pixel
		image.x = text.x - text.width - ICON_TEXT_GAP * pixel - icon.width * pixel
		if frame then
			frame:removeSelf()
		end
		local width = Frame.snap(right - image.x + (FRAME_PADDING + 0.5) * pixel, pixel)
		left = right - width
		frame = Frame.new(group, left, rect.minY, width, rect.size, "frame", pixel)
		frame:toBack()
		return left
	end
end

function Hud.create()
	local rect = Layout.getHudRect()
	local pixel = rect.pixel
	local stage = display.getCurrentStage()

	local barnButton = newButton(stage, rect.minX, rect, BARN_ICON_PATH, BarnView.show)
	local shopX = rect.minX - BUTTON_GAP * pixel - rect.size
	newButton(stage, shopX, rect, SHOP_ICON_PATH, ShopView.show)
	DropZone.onLanded(function(area)
		if area == "barn" then
			barnButton.flash()
		end
	end)

	local counters = display.newGroup()
	local updateEggs = newCounter(counters, rect, EGG_ICON)
	local updateCoins = newCounter(counters, rect, COIN_ICON)

	local function refresh()
		local eggLeft = updateEggs(Garden.getCollectedCount(), shopX - BUTTON_GAP * pixel)
		updateCoins(Wallet.get(), eggLeft - BUTTON_GAP * pixel)
	end
	refresh()
	Runtime:addEventListener("enterFrame", refresh)

	-- The shop keeps the counters showing, moved up to the screen's top
	-- beside its X (ADR-0031); the barn view covers them.
	local viewOffset = Layout.getViewHudRect().minY - rect.minY
	local function liftCounters()
		counters:toFront()
		counters.y = viewOffset
	end
	local function lowerCounters()
		counters.y = 0
	end
	ShopView.onShown(liftCounters)
	ShopView.onHidden(lowerCounters)
end

return Hud
