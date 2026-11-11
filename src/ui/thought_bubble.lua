local Constants = require("src.util.constants")
local Hearts = require("src.objects.hearts")
local WelcomeCard = require("src.ui.welcome_card")

-- Thought bubbles (CONTEXT.md): one on screen at a time across the garden,
-- an egg bubble before a need bubble. Timers are real time, not sim time.
local ThoughtBubble = {}

local BUBBLE_PATH = "assets/ui/thought_bubble.png"
-- The same egg art as the world and the HUD, at twice the bubble's pixel
-- size so it fills the slot and stays on the bubble's pixel grid.
local EGG_ICON = "assets/fauna/ChickenEgg.png"
local EGG_WIDTH, EGG_HEIGHT, EGG_SCALE = 6, 7, 2
-- Art in native px: the tail dot's centre is TAIL_X from the left edge, at
-- the bottom; the 16x16 icon slot's centre sits at SLOT_X, SLOT_Y.
local ART_WIDTH, ART_HEIGHT = 22, 29
local TAIL_X = 1
local SLOT_X, SLOT_Y = 11, 11
local ICON_SIZE = 16

local POP_TIME = 150 -- ms
local SHOW_TIME = 5000
local GATE_SHOW_TIME = 8000 -- a gauge at the lay gate asks longer and sooner
local FADE_TIME = 1000
local QUICK_FADE_TIME = 300 -- held back, or making way for an egg bubble
local RETURN_TIME = { min = 30000, max = 120000 }
local GATE_RETURN_TIME = { min = 30000, max = 60000 }
local NO_BED_EGG_TIME = 2000

local current = nil -- { chicken, kind, group, endsAt, atGate, fading }
local nextNeedAt = setmetatable({}, { __mode = "k" }) -- chicken -> ms

local function randomIn(range)
	return range.min + math.random() * (range.max - range.min)
end

-- An egg bubble wanted for this chicken right now (walking to lay, or a
-- no-bed lay just happened).
local function wantsEgg(chicken, now)
	return chicken.wantsEggBubble or now < (chicken.eggFlashUntil or 0)
end

-- Places the bubble so its tail dot sits just above her head, mirrored for
-- a hen facing left. Only the bubble flips; the icon never does.
local function place(entry)
	local x, y, facing = entry.chicken:getBubbleAnchor()
	local scale = Constants.UI_PIXEL_SCALE
	local group = entry.group
	group.x, group.y = x, y
	group.bubble.xScale = facing
	group.bubble.x = -facing * TAIL_X * scale
	group.icon.x = facing * (SLOT_X - TAIL_X) * scale
end

local function show(chicken, kind, iconPath, now, atGate)
	local scale = Constants.UI_PIXEL_SCALE
	local group = display.newGroup()
	Hearts.getLayer():insert(group)

	local bubble = display.newImageRect(group, BUBBLE_PATH, ART_WIDTH * scale, ART_HEIGHT * scale)
	bubble.anchorX, bubble.anchorY = 0, 1
	local iconWidth, iconHeight = ICON_SIZE, ICON_SIZE
	if iconPath == EGG_ICON then
		iconWidth, iconHeight = EGG_WIDTH * EGG_SCALE, EGG_HEIGHT * EGG_SCALE
	end
	local icon = display.newImageRect(group, iconPath, iconWidth * scale, iconHeight * scale)
	icon.y = -(ART_HEIGHT - SLOT_Y) * scale
	group.bubble, group.icon = bubble, icon

	-- Opens her tooltip, even with an item selected.
	bubble:addEventListener("tap", function()
		chicken:showTooltip()
		return true
	end)

	group.alpha = 0
	transition.to(group, { alpha = 1, time = POP_TIME })

	local showTime = atGate and GATE_SHOW_TIME or SHOW_TIME
	current = { chicken = chicken, kind = kind, group = group, endsAt = now + showTime, atGate = atGate }
	place(current)
end

local function fade(time)
	local entry = current
	entry.fading = true
	transition.cancel(entry.group)
	transition.to(entry.group, {
		alpha = 0,
		time = time,
		onComplete = function()
			entry.group:removeSelf()
			if entry.kind == "need" then
				local range = entry.atGate and GATE_RETURN_TIME or RETURN_TIME
				nextNeedAt[entry.chicken] = system.getTimer() + randomIn(range)
			end
			if current == entry then
				current = nil
			end
		end,
	})
end

-- A no-bed lay: she lays where she stands, so the egg bubble shows briefly.
function ThoughtBubble.flashEgg(chicken)
	chicken.eggFlashUntil = system.getTimer() + NO_BED_EGG_TIME
end

-- Called every frame by Garden with its chickens and what's out.
function ThoughtBubble.update(chickens, hasFood, hasWater)
	local now = system.getTimer()
	local cardUp = WelcomeCard.isShowing()

	local eggWaiting = false
	for _, chicken in ipairs(chickens) do
		if wantsEgg(chicken, now) and not chicken:isBubbleHeldBack(false) then
			eggWaiting = true
		end
		-- A met need starts over: it shows at once if it comes back.
		if not chicken:getUnmetNeed(hasFood, hasWater) then
			nextNeedAt[chicken] = nil
		end
	end

	if current and not current.fading then
		local chicken = current.chicken
		place(current)
		if current.kind == "egg" then
			if not wantsEgg(chicken, now) then
				fade(FADE_TIME)
			elseif cardUp or chicken:isBubbleHeldBack(false) then
				fade(QUICK_FADE_TIME)
			end
		elseif cardUp or eggWaiting or chicken:isBubbleHeldBack(true) then
			fade(QUICK_FADE_TIME)
		elseif now >= current.endsAt or not chicken:getUnmetNeed(hasFood, hasWater) then
			fade(FADE_TIME)
		end
	elseif current then
		place(current)
	end
	if current or cardUp then
		return
	end

	for _, chicken in ipairs(chickens) do
		if wantsEgg(chicken, now) and not chicken:isBubbleHeldBack(false) then
			show(chicken, "egg", EGG_ICON, now, false)
			return
		end
	end

	-- Needs take turns: the hen whose worst gauge is lowest goes first.
	local best, bestNeed, bestGate, bestValue
	for _, chicken in ipairs(chickens) do
		local need, atGate, value = chicken:getUnmetNeed(hasFood, hasWater)
		if need and not chicken:isBubbleHeldBack(true) and now >= (nextNeedAt[chicken] or 0)
			and (not bestValue or value < bestValue) then
			best, bestNeed, bestGate, bestValue = chicken, need, atGate, value
		end
	end
	if best then
		show(best, "need", best.ICONS[bestNeed], now, bestGate)
	end
end

return ThoughtBubble
