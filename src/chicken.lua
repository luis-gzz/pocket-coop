local StateMachine = require("src.state_machine")
local Constants = require("src.constants")
local Island = require("src.island")

local Chicken = {}
Chicken.__index = Chicken

local SPRITE_SIZE = 16
-- Shared with the island tiles so pixel density matches across all art.
local DISPLAY_SCALE = Constants.PIXEL_SCALE
local SHEET_PATH = "assets/fauna/CHICKEN/"
local COLOR = "LightBrown"

local SHADOW_PATH = "assets/fauna/CHICKEN/chickenShadow.png"
local SHADOW_WIDTH, SHADOW_HEIGHT = 15, 5

local IDLE_DWELL = { min = 2, max = 4 } -- seconds
local EAT_DWELL = { min = 2, max = 4 } -- seconds
local WANDER_MIN_RADIUS = 20
local WANDER_MAX_RADIUS = 60
local WANDER_SPEED = 40 -- points per second

local WIGGLE_ANGLE = 8
local WIGGLE_STEP_TIME = 90

-- Fixed round-robin cycle: idle -> eat -> wander -> idle -> ...
local NEXT_STATE = {
	idle = "eat",
	eat = "wander",
	wander = "idle",
}

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

function Chicken.new()
	local self = setmetatable({}, Chicken)

	local spawnBounds = getBounds()

	self.view = display.newGroup()
	self.view.x = (spawnBounds.minX + spawnBounds.maxX) / 2
	self.view.y = (spawnBounds.minY + spawnBounds.maxY) / 2
	self.view.xScale = DISPLAY_SCALE
	self.view.yScale = DISPLAY_SCALE
	self.facing = 1

	local shadow = display.newImageRect(self.view, SHADOW_PATH, SHADOW_WIDTH, SHADOW_HEIGHT)
	shadow.x = 0
	shadow.y = SPRITE_SIZE / 2

	-- Everything but the shadow lives in body, since that's the part that
	-- wiggles when the chicken is picked up - the shadow stays flat.
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

	self:setupDrag()
	self.machine = StateMachine.new(self, STATES, "idle")

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

function Chicken:setupDrag()
	local function onTouch(event)
		local view = self.view
		if event.phase == "began" then
			display.getCurrentStage():setFocus(view, event.id)
			view.isFocus = true
			self.dragOffsetX = view.x - event.x
			self.dragOffsetY = view.y - event.y
			self.machine:pause()
			self:setAnimation("idle")
			self:startWiggle()
		elseif view.isFocus then
			if event.phase == "moved" then
				local bounds = getBounds()
				view.x = clamp(event.x + self.dragOffsetX, bounds.minX, bounds.maxX)
				view.y = clamp(event.y + self.dragOffsetY, bounds.minY, bounds.maxY)
			elseif event.phase == "ended" or event.phase == "cancelled" then
				display.getCurrentStage():setFocus(view, nil)
				view.isFocus = false
				self:stopWiggle()
			end
		end
		return true
	end
	self.view:addEventListener("touch", onTouch)
end

-- Wiggles continuously while the player holds the chicken; stopWiggle()
-- settles it back to a neutral rotation and resumes the FSM. Rotates only
-- the body, so the shadow stays flat on the ground.
function Chicken:startWiggle()
	self.isDragging = true

	local body = self.body
	local nextAngle = WIGGLE_ANGLE
	local function step()
		if not self.isDragging then
			return
		end
		self.wiggleHandle = transition.to(body, {
			rotation = nextAngle,
			time = WIGGLE_STEP_TIME,
			onComplete = step,
		})
		nextAngle = -nextAngle
	end
	step()
end

function Chicken:stopWiggle()
	self.isDragging = false
	if self.wiggleHandle then
		transition.cancel(self.wiggleHandle)
		self.wiggleHandle = nil
	end
	transition.to(self.body, {
		rotation = 0,
		time = WIGGLE_STEP_TIME,
		onComplete = function()
			self.machine:changeState("idle")
		end,
	})
end

STATES = {
	idle = {
		enter = function(chicken)
			chicken:setAnimation("idle")
			chicken.timerHandle = timer.performWithDelay(randomDwell(IDLE_DWELL), function()
				chicken.machine:changeState(NEXT_STATE.idle)
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
			chicken.timerHandle = timer.performWithDelay(randomDwell(EAT_DWELL), function()
				chicken.machine:changeState(NEXT_STATE.eat)
			end)
		end,
		exit = function(chicken)
			if chicken.timerHandle then
				timer.cancel(chicken.timerHandle)
				chicken.timerHandle = nil
			end
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
					chicken.machine:changeState(NEXT_STATE.wander)
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
}

return Chicken
