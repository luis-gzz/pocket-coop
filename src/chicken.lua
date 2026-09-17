local StateMachine = require("src.state_machine")
local Constants = require("src.constants")
local Island = require("src.island")
local YSort = require("src.y_sort")
local Gauges = require("src.gauges")
local Dropping = require("src.dropping")
local Coop = require("src.coop")
local TimeScale = require("src.time_scale")
local Tooltip = require("src.tooltip")
local Wiggle = require("src.wiggle")

local Chicken = {}
Chicken.__index = Chicken

local SPRITE_SIZE = 16
-- Shared with the island tiles so pixel density matches across all art.
local DISPLAY_SCALE = Constants.PIXEL_SCALE
local SHEET_PATH = "assets/fauna/CHICKEN/"
local COLOR = "LightBrown"

local SHADOW_PATH = "assets/fauna/CHICKEN/chickenShadow.png"
local SHADOW_WIDTH, SHADOW_HEIGHT = 15, 5

-- view.y is the sprite's vertical center; SPRITE_SIZE / 2 (scaled by
-- DISPLAY_SCALE) reaches the sprite's actual bottom edge - confirmed
-- pixel-accurate against the idle/walk/eat sheets, none of which have
-- transparent padding at the bottom of their 16x16 frame. Used as a depth
-- offset for Y-sort (ADR-0006) so the chicken sorts by its feet (bottom),
-- not its sprite center.
local GROUND_OFFSET = (SPRITE_SIZE / 2) * DISPLAY_SCALE

local SELECTED_PATH = "assets/fauna/CHICKEN/chickeSelected.png"

local HEART_PATH = "assets/fauna/heart.png"
local HEART_WIDTH, HEART_HEIGHT = 9 * DISPLAY_SCALE, 9 * DISPLAY_SCALE

local IDLE_DWELL = { min = 2, max = 4 } -- seconds
local IDLE_WANDER_SPLIT = 0.4 -- probability of idle vs wander when not forced to eat
local WANDER_MIN_RADIUS = 20
local WANDER_MAX_RADIUS = 60
local WANDER_SPEED = 40 -- points per second

local WIGGLE_ANGLE = 8
local WIGGLE_STEP_TIME = 90
local LONG_PRESS_TIME = 350 -- ms; shorter touches open the tooltip instead

local STATES -- assigned near the bottom, after the methods it calls exist

local function randomDwell(range)
	return math.random(range.min * 1000, range.max * 1000)
end

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

-- Keeps the chicken (idle, wander, and drag) inside the island's play area,
-- which is itself already inset from the island's outer border tiles. The
-- top is allowed to go half a sprite further, so the chicken can walk half
-- off the top edge instead of stopping flush against it.
local function getBounds()
	local rect = Island.getInnerBounds()
	local halfSize = (SPRITE_SIZE * DISPLAY_SCALE) / 2
	return {
		minX = rect.minX + halfSize,
		maxX = rect.maxX - halfSize,
		minY = rect.minY,
		maxY = rect.maxY - halfSize,
	}
end

local function pickWanderDestination(chicken)
	local bounds = getBounds()
	local angle = math.random() * math.pi * 2
	local radius = math.random(WANDER_MIN_RADIUS, WANDER_MAX_RADIUS)
	local x = clamp(chicken.view.x + math.cos(angle) * radius, bounds.minX, bounds.maxX)
	local y = clamp(chicken.view.y + math.sin(angle) * radius, bounds.minY, bounds.maxY)
	return x, y
end

-- Once satiety is comfortable, idle/wander alternate on a weighted flip
-- instead of a fixed round-robin; hungry always wins via hysteresis (enter
-- below EAT_ENTER_THRESHOLD, stay until above EAT_EXIT_THRESHOLD - see
-- src/gauges.lua). While selected (its tooltip is open), wander is dropped
-- entirely so it can't drift away mid-conversation.
local function decideNextState(chicken)
	if chicken.gauges:isHungry() then
		return "eat"
	end
	if chicken.selected then
		return "idle"
	end
	return (math.random() < IDLE_WANDER_SPLIT) and "idle" or "wander"
end

local function buildSprite(path, numFrames, frameTime)
	local sheet = graphics.newImageSheet(path, {
		width = SPRITE_SIZE,
		height = SPRITE_SIZE,
		numFrames = numFrames,
		sheetContentWidth = SPRITE_SIZE * numFrames,
		sheetContentHeight = SPRITE_SIZE,
	})
	local sequenceData = { name = "play", start = 1, count = numFrames, time = frameTime, loopCount = 0 }
	local sprite = display.newSprite(sheet, sequenceData)
	sprite.isVisible = false
	return sprite
end

-- saved: an optional table from src/save.lua (position + Gauges fields) to
-- resume from.
function Chicken.new(saved)
	local self = setmetatable({}, Chicken)

	self.gauges = Gauges.new(saved)
	self.droppingViews = {}
	self.selected = false

	local spawnBounds = getBounds()

	self.view = display.newGroup()
	YSort.getGroup():insert(self.view)
	self.view.x = (saved and saved.x) or (spawnBounds.minX + spawnBounds.maxX) / 2
	self.view.y = (saved and saved.y) or (spawnBounds.minY + spawnBounds.maxY) / 2
	self.view.xScale = DISPLAY_SCALE
	self.view.yScale = DISPLAY_SCALE
	self.facing = 1
	YSort.add(self.view, function(view)
		return view.y + GROUND_OFFSET
	end)

	local shadow = display.newImageRect(self.view, SHADOW_PATH, SHADOW_WIDTH, SHADOW_HEIGHT)
	shadow.x = 0
	shadow.y = SPRITE_SIZE / 2

	-- Same spot as the shadow, rendered on top of it (inserted right after);
	-- shown only while the chicken's tooltip is open.
	self.selectedIndicator = display.newImageRect(self.view, SELECTED_PATH, SHADOW_WIDTH, SHADOW_HEIGHT)
	self.selectedIndicator.x = 0
	self.selectedIndicator.y = SPRITE_SIZE / 2
	self.selectedIndicator.isVisible = false

	-- A dedicated hit target for touch/setFocus: Solar2D's touch focus can be
	-- unreliable on a bare display.newGroup() (no drawable content of its
	-- own), which showed up as taps silently doing nothing.
	self.hitArea = display.newRect(self.view, 0, 0, SPRITE_SIZE, SPRITE_SIZE)
	self.hitArea:setFillColor(0, 0, 0, 0.01)

	-- Everything but the shadow lives in body, since that's the part that
	-- wiggles when the chicken is held - the shadow stays flat.
	self.body = display.newGroup()
	self.view:insert(self.body)

	self.sprites = {
		idle = buildSprite(SHEET_PATH .. "Idle/" .. COLOR .. "ChickenIdle-Sheet.png", 2, 600),
		walk = buildSprite(SHEET_PATH .. "Walking/" .. COLOR .. "ChickenWalking-Sheet.png", 4, 500),
		eat = buildSprite(SHEET_PATH .. "Eating/" .. COLOR .. "ChickenEating-Sheet.png", 6, 700),
	}
	for _, sprite in pairs(self.sprites) do
		self.body:insert(sprite)
	end

	for _, record in ipairs(self.gauges.droppings) do
		self:addDroppingView(record)
	end

	self:setupTouch()
	self.machine = StateMachine.new(self, STATES, "idle")
	self:setupUpdateLoop()

	return self
end

function Chicken:setAnimation(name)
	if self.activeSprite then
		self.activeSprite.isVisible = false
		self.activeSprite:pause()
	end
	local sprite = self.sprites[name]
	sprite.isVisible = true
	sprite:setFrame(1)
	sprite:play()
	self.activeSprite = sprite
end

function Chicken:setFacing(direction)
	if direction ~= 0 and direction ~= self.facing then
		self.facing = direction
		self.view.xScale = DISPLAY_SCALE * direction
	end
end

-- While selected (its tooltip is open), the chicken can only idle/eat - see
-- decideNextState. Cuts a wander already in progress short so it can't drift
-- away right as the tooltip appears.
function Chicken:setSelected(value)
	self.selected = value
	self.selectedIndicator.isVisible = value
	if value and self.machine.name == "wander" then
		self.machine:changeState("idle")
	end
end

function Chicken:addDroppingView(record)
	local dropping = Dropping.new(record, function(view)
		self.gauges:removeDropping(view.record)
		view:destroy()
		for index, existing in ipairs(self.droppingViews) do
			if existing == view then
				table.remove(self.droppingViews, index)
				break
			end
		end
	end)
	table.insert(self.droppingViews, dropping)
end

-- Applied on every short tap (see setupTouch), in addition to opening the
-- tooltip. A no-op while the pet buff is already active, so repeat taps
-- neither extend the buff nor replay the heart bubble animation.
function Chicken:pet()
	if self.gauges:isPetBuffActive() then
		return
	end
	self.gauges:applyPetBuff()
	self:showHeartBubble()
end

function Chicken:showHeartBubble()
	local heart = display.newImageRect(HEART_PATH, HEART_WIDTH, HEART_HEIGHT)
	heart.x = self.view.x
	heart.y = self.view.y - SPRITE_SIZE * DISPLAY_SCALE
	transition.to(heart, {
		y = heart.y - 20,
		alpha = 0,
		time = 800,
		onComplete = function()
			heart:removeSelf()
		end,
	})
end

-- Drives the gauges every frame (independent of FSM state - satiety etc.
-- keep updating while held, per the design), spawns visuals for any new
-- droppings, and forces an exit out of Eat once satiety is comfortable
-- again (Eat has no dwell timer of its own; see src/gauges.lua).
function Chicken:setupUpdateLoop()
	local lastFrameTime = nil

	local function onFrame(event)
		if not lastFrameTime then
			lastFrameTime = event.time
			return
		end
		local dt = (event.time - lastFrameTime) / 1000
		lastFrameTime = event.time

		local spawned, laid = self.gauges:update(dt, TimeScale.get(), self.view.x, self.view.y)
		for _, record in ipairs(spawned) do
			self:addDroppingView(record)
		end
		if laid then
			Coop.hatchEgg(self.view.x, self.view.y)
		end

		if self.machine.name == "eat" and self.gauges:isFull() then
			self.machine:changeState(decideNextState(self))
		end
	end

	Runtime:addEventListener("enterFrame", onFrame)
end

function Chicken:getSaveData()
	local data = self.gauges:getSaveData()
	data.x = self.view.x
	data.y = self.view.y
	return data
end

-- Distinguishes a short tap (opens the tooltip) from a long press (picks
-- the chicken up) by hold duration.
function Chicken:setupTouch()
	local hitArea = self.hitArea

	local function beginHeld(x, y)
		if self.selected then
			self:setSelected(false)
			Tooltip:hide()
		end

		local view = self.view
		self.dragOffsetX = view.x - x
		self.dragOffsetY = view.y - y
		self.machine:changeState("held")
	end

	local function onTouch(event)
		if event.phase == "began" then
			display.getCurrentStage():setFocus(hitArea, event.id)
			hitArea.isFocus = true
			self.pendingTouch = true
			local startX, startY = event.x, event.y
			self.longPressHandle = timer.performWithDelay(LONG_PRESS_TIME, function()
				self.longPressHandle = nil
				if self.pendingTouch then
					beginHeld(startX, startY)
					self.pendingTouch = nil
				end
			end)
		elseif hitArea.isFocus then
			if event.phase == "moved" then
				if self.machine.name == "held" then
					local view = self.view
					local bounds = getBounds()
					view.x = clamp(event.x + self.dragOffsetX, bounds.minX, bounds.maxX)
					view.y = clamp(event.y + self.dragOffsetY, bounds.minY, bounds.maxY)
				end
			elseif event.phase == "ended" or event.phase == "cancelled" then
				display.getCurrentStage():setFocus(hitArea, nil)
				hitArea.isFocus = false

				if self.longPressHandle then
					timer.cancel(self.longPressHandle)
					self.longPressHandle = nil
					self.pendingTouch = nil
					if event.phase == "ended" then
						-- Show the tooltip first so the heart bubble (created
						-- by pet(), with no explicit parent group) is inserted
						-- after it and renders on top instead of underneath.
						Tooltip.show(self)
						self:pet()
					end
				elseif self.machine.name == "held" then
					self.machine:changeState(decideNextState(self))
				end
			end
		end
		return true
	end
	hitArea:addEventListener("touch", onTouch)
end

-- Wiggles continuously while the chicken is held; stopWiggle() settles it
-- back to a neutral rotation. Rotates only the body, so the shadow stays
-- flat on the ground.
function Chicken:startWiggle()
	self.isHeld = true
	self.wiggleHandle = Wiggle.start(self.body, WIGGLE_ANGLE, WIGGLE_STEP_TIME, function()
		return self.isHeld
	end)
end

function Chicken:stopWiggle()
	self.isHeld = false
	Wiggle.stop(self.wiggleHandle)
	self.wiggleHandle = nil
end

STATES = {
	idle = {
		enter = function(chicken)
			chicken:setAnimation("idle")
			chicken.timerHandle = timer.performWithDelay(randomDwell(IDLE_DWELL), function()
				chicken.machine:changeState(decideNextState(chicken))
			end)
		end,
		exit = function(chicken)
			if chicken.timerHandle then
				timer.cancel(chicken.timerHandle)
				chicken.timerHandle = nil
			end
		end,
	},

	eat = {
		enter = function(chicken)
			chicken:setAnimation("eat")
			chicken.gauges:setEating(true)
		end,
		exit = function(chicken)
			chicken.gauges:setEating(false)
		end,
	},

	wander = {
		enter = function(chicken)
			chicken:setAnimation("walk")

			local destX, destY = pickWanderDestination(chicken)
			chicken:setFacing(destX < chicken.view.x and -1 or 1)

			local distance = math.sqrt((destX - chicken.view.x) ^ 2 + (destY - chicken.view.y) ^ 2)
			local duration = math.max(200, (distance / WANDER_SPEED) * 1000)

			chicken.transitionHandle = transition.to(chicken.view, {
				x = destX,
				y = destY,
				time = duration,
				onComplete = function()
					chicken.transitionHandle = nil
					chicken.machine:changeState(decideNextState(chicken))
				end,
			})
		end,
		exit = function(chicken)
			if chicken.transitionHandle then
				transition.cancel(chicken.transitionHandle)
				chicken.transitionHandle = nil
			end
		end,
	},

	held = {
		enter = function(chicken)
			chicken:setAnimation("idle")
			chicken:startWiggle()
		end,
		exit = function(chicken)
			chicken:stopWiggle()
		end,
	},
}

return Chicken
