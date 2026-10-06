local StateMachine = require("src.util.state_machine")
local Constants = require("src.util.constants")
local Layout = require("src.ui.layout")
local YSort = require("src.systems.y_sort")
local Gauges = require("src.objects.chicken.gauges")
local Clock = require("src.systems.clock")
local Tuning = require("src.systems.tuning")
local Feed = require("src.systems.feed")
local Tooltip = require("src.ui.tooltip")
local Wiggle = require("src.util.wiggle")

local Chicken = {}
Chicken.__index = Chicken

local SPRITE_SIZE = 16
-- Shared with the ground tiles so pixel density matches across all art.
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

-- Shown in the tooltip's buff row while a happiness buff is active.
local HEART_PATH = "assets/fauna/heart.png"
local HEART_ICON_SIZE = 9 * DISPLAY_SCALE

local IDLE_DWELL = { min = 2, max = 4 } -- sim-seconds
local IDLE_WANDER_SPLIT = 0.4 -- probability of idle vs wander when not eating
local WANDER_MIN_RADIUS = 20
local WANDER_MAX_RADIUS = 60
local WANDER_SPEED = 40 -- points per second

-- How far past a food source's edge a chicken stands to eat, randomized so
-- repeat visits don't land on the same spot.
local EAT_STANDOFF_MIN_JITTER = 2
local EAT_STANDOFF_MAX_JITTER = 8

local WIGGLE_ANGLE = 8
local WIGGLE_STEP_TIME = 90
local LONG_PRESS_TIME = 350 -- ms; shorter touches open the tooltip instead

-- How long a chicken plays the eat animation after finishing a mealworm.
local TREAT_EAT_DURATION = 2 -- sim-seconds

local STATES -- assigned near the bottom, after the methods it calls exist

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

-- Keeps the chicken's whole sprite (idle, wander, and drag) inside the play
-- area, so it never pokes into the UI bands.
local function getBounds()
	local rect = Layout.getPlayArea()
	local halfSize = (SPRITE_SIZE * DISPLAY_SCALE) / 2
	return {
		minX = rect.minX + halfSize,
		maxX = rect.maxX - halfSize,
		minY = rect.minY + halfSize,
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

-- Picks a point just past a food item's edge, in a random direction, so the
-- chicken stands slightly to the side rather than on dead center (which
-- would obscure a small item like a mealworm from view entirely).
local function pickEatingSpot(target)
	local angle = math.random() * math.pi * 2
	local jitter = EAT_STANDOFF_MIN_JITTER + math.random() * (EAT_STANDOFF_MAX_JITTER - EAT_STANDOFF_MIN_JITTER)
	local radius = target.width / 2 + jitter
	local bounds = getBounds()
	local x = clamp(target.x + math.cos(angle) * radius, bounds.minX, bounds.maxX)
	local y = clamp(target.y + math.sin(angle) * radius, bounds.minY, bounds.maxY)
	return x, y
end

-- Where a hungry chicken goes next (ADR-0015): "approach" (food cycle),
-- "eat" (forage cycle), or nil if not hungry, on a bout break, or food vanished.
local function pickHungerState(chicken)
	if chicken.onBoutBreak then
		return nil
	end
	local mode = chicken.gauges:getHungerMode()
	if mode == "food" then
		local target = Feed.findNearestSource(chicken.view.x, chicken.view.y)
		if target then
			chicken:setFoodTarget(target)
			return "approach"
		end
	elseif mode == "forage" then
		chicken:setFoodTarget(nil)
		return "eat"
	end
	return nil
end

local function decideNextState(chicken)
	local hungerState = pickHungerState(chicken)
	if hungerState then
		return hungerState
	end

	chicken:setFoodTarget(nil)
	if chicken.selected then
		return "idle"
	end
	return (math.random() < IDLE_WANDER_SPLIT) and "idle" or "wander"
end

-- Ends a bout of eating. A food cycle that isn't finished yet (satiety still
-- short of 100) takes a short sim-time break before the next bout.
local function finishBout(chicken)
	chicken:setFoodTarget(nil)
	if chicken.gauges:isHungry() then
		chicken:startBoutBreak()
	end
	chicken.machine:changeState(decideNextState(chicken))
end

-- Applies the treat's payoff and removes it immediately; the chicken still
-- lingers in "eatTreat" afterward to play the eat animation.
local function consumeTreat(chicken)
	local target = chicken.foodTarget
	chicken.gauges:applyTreat(target.fullness)
	chicken.gauges:applyHappinessBuff()
	Feed.consumeTreat(target)
	chicken:setFoodTarget(nil)
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

-- saved: an optional table from src/systems/save.lua (position + Gauges
-- fields) to resume from. layCallbacks = { pickLayTarget, commitLay }, both
-- owned by Garden (ADR-0013) - injected rather than required directly, the
-- same way Bed/Mealworm receive their own placement callbacks from Garden,
-- so this module never needs to require Garden itself.
function Chicken.new(saved, layCallbacks)
	local self = setmetatable({}, Chicken)

	self.gauges = Gauges.new(saved)
	self.selected = false
	self.layCallbacks = layCallbacks

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

	-- A dedicated hit target (a bare group's touch focus is unreliable), kept
	-- as a world-group sibling and pushed toFront() every frame for touch priority.
	self.hitArea = display.newRect(
		YSort.getGroup(), self.view.x, self.view.y, SPRITE_SIZE * DISPLAY_SCALE, SPRITE_SIZE * DISPLAY_SCALE
	)
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

	self:setupTouch()
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

-- Opening the tooltip stops whatever the chicken was doing and drops it to idle.
function Chicken:setSelected(value)
	self.selected = value
	self.selectedIndicator.isVisible = value
	if value and self.machine.name ~= "idle" and self.machine.name ~= "held" then
		self:setFoodTarget(nil)
		self:cancelNesting()
		self.machine:changeState("idle")
	end
end

-- Abandons an in-progress walk to lay, letting lay progress fire again
-- (ADR-0013) - called wherever a food target is also abandoned, since an
-- interrupted walk means the hen never actually reached its target. Without
-- this, gauges.pendingLay would stay set forever and the hen could never lay
-- again.
function Chicken:cancelNesting()
	self.layTarget = nil
	self.gauges.pendingLay = false
end

-- target: one of Garden.pickLayTarget's results. "immediate" lays right
-- where the hen stands (no beds exist anywhere); anything else walks there
-- first via the "nest" state. Preempts whatever the hen was doing, the same
-- way a treat's claim does, and releases any food target/claim first.
function Chicken:beginNesting(target)
	self:setFoodTarget(nil)
	if target.kind == "immediate" then
		self.layCallbacks.commitLay(target, self.view.x, self.view.y)
		self.gauges:markLaid()
		return
	end
	self.layTarget = target
	self.machine:changeState("nest")
end

function Chicken:startBoutBreak()
	self:cancelBoutBreak()
	self.onBoutBreak = true
	self.boutBreakHandle = Clock.after(Tuning.randomIn(Tuning.BOUT_BREAK), function()
		self.boutBreakHandle = nil
		self.onBoutBreak = false
	end)
end

function Chicken:cancelBoutBreak()
	Clock.cancel(self.boutBreakHandle)
	self.boutBreakHandle = nil
	self.onBoutBreak = false
end

-- Drops whatever the chicken was doing before offline catch-up (ADR-0016).
-- Lay progress is kept, so a pending egg is counted by catch-up instead.
function Chicken:resetForCatchUp()
	self:setFoodTarget(nil)
	self:cancelNesting()
	self:cancelBoutBreak()
	self.gauges:resetHunger()
	if self.machine.name ~= "held" then
		self.machine:changeState("idle")
	end
end

-- Releases a superseded treat's claim before adopting a new target.
function Chicken:setFoodTarget(newTarget)
	local old = self.foodTarget
	if old and old ~= newTarget and old.kind == "treat" then
		Feed.releaseTreatClaim(old)
	end
	self.foodTarget = newTarget
end

-- Re-enters "approach" so a chicken following a dragged treat re-paths
-- toward its live position.
function Chicken:retargetApproach()
	if self.machine.name == "approach" then
		self.machine:changeState("approach")
	end
end

function Chicken:getPosition()
	return self.view.x, self.view.y
end

-- A random point within the chicken's movement bounds, where it reappears
-- after offline catch-up.
function Chicken.randomSpot()
	local bounds = getBounds()
	return bounds.minX + math.random() * (bounds.maxX - bounds.minX),
		bounds.minY + math.random() * (bounds.maxY - bounds.minY)
end

-- Moves the chicken instantly, hit target included. Callers stop any walk
-- first (resetForCatchUp does).
function Chicken:teleportTo(x, y)
	self.view.x, self.view.y = x, y
	self.hitArea.x, self.hitArea.y = x, y
end

-- Driven every frame by garden.lua's own frame loop (not a private listener
-- here - see garden.lua for why): drives the gauges, debits any food source
-- being eaten from, and checks for a nearby treat alert. dt is already
-- time-scaled (from Clock); dirt is the garden-wide dropping + floor egg
-- penalty. Returns any newly spawned dropping records and whether a
-- lay happened this call, so Garden can create their views / hatch the egg -
-- both are Garden-owned concerns now, not this chicken's.
function Chicken:update(dt, dirt, hasSource)
	-- Keeps the hit target glued to the chicken and always frontmost.
	self.hitArea.x = self.view.x
	self.hitArea.y = self.view.y
	self.hitArea:toFront()

	local isHeld = self.machine.name == "held"
	local spawned, laid, delivered, boutDone = self.gauges:update(
		dt, dirt, self.view.x, self.view.y, isHeld, hasSource
	)

	-- Debits the food source by the satiety actually delivered this frame.
	if self.machine.name == "eat" and self.foodTarget and delivered > 0 then
		if not Feed.deplete(self.foodTarget, delivered) then
			self:setFoodTarget(nil)
			self.machine:changeState(decideNextState(self))
		end
	end

	if self.machine.name == "eat" and boutDone then
		finishBout(self)
	end

	-- Hunger is acted on here, not at the next re-decide, so high time scale
	-- can't overshoot it. Interrupts idle/wander, or foraging once food appears.
	local state = self.machine.name
	local isForaging = state == "eat" and not self.foodTarget
	local interruptible = state == "idle" or state == "wander"
		or (isForaging and self.gauges:getHungerMode() == "food")
	if interruptible and not self.selected then
		local hungerState = pickHungerState(self)
		if hungerState then
			self.machine:changeState(hungerState)
		end
	end

	-- A treat alert is checked every frame and preempts whatever the
	-- chicken is doing, except while held - including an in-progress nest
	-- walk, so cancelNesting() releases that lay attempt the same way it
	-- does for any other interruption.
	if self.machine.name ~= "held" then
		local claimed = Feed.claimTreatNear(self, self.view.x, self.view.y)
		if claimed then
			self:cancelNesting()
			self:setFoodTarget(claimed)
			self.machine:changeState("approach")
		end
	end

	return spawned, laid
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
						Tooltip.show({
							x = self.view.x,
							y = self.view.y,
							onShow = function()
								self:setSelected(true)
							end,
							onHide = function()
								self:setSelected(false)
							end,
							rows = {
								{ label = "Fullness", getValue = function() return self.gauges.satiety end },
								{ label = "Cleanliness", getValue = function() return self.gauges.cleanliness end },
								{ label = "Happiness", getValue = function() return self.gauges:getHappiness() end },
							},
							buffs = {
								{
									icon = HEART_PATH,
									size = HEART_ICON_SIZE,
									isActive = function() return self.gauges:isHappinessBuffActive() end,
								},
							},
						})
					end
				elseif self.machine.name == "held" then
					self.machine:changeState(decideNextState(self))
				end
			end
		end
		return true
	end
	hitArea:addEventListener("touch", onTouch)

	-- Solar2D hit-tests "tap" separately from "touch" and skips objects with
	-- no "tap" listener - this blocks a tap falling through to what's underneath.
	hitArea:addEventListener("tap", function()
		return true
	end)
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
			chicken.timerHandle = Clock.after(Tuning.randomIn(IDLE_DWELL), function()
				chicken.timerHandle = nil
				chicken.machine:changeState(decideNextState(chicken))
			end)
		end,
		exit = function(chicken)
			Clock.cancel(chicken.timerHandle)
			chicken.timerHandle = nil
		end,
	},

	-- Walks to a claimed food item; arrival hands off to "eat" for a source
	-- or consumes a treat outright.
	approach = {
		enter = function(chicken)
			local target = chicken.foodTarget
			if not target or target.removed then
				chicken:setFoodTarget(nil)
				chicken.machine:changeState(decideNextState(chicken))
				return
			end

			chicken:setAnimation("walk")

			local destX, destY = pickEatingSpot(target)
			chicken:setFacing(destX < chicken.view.x and -1 or 1)

			local distance = math.sqrt((destX - chicken.view.x) ^ 2 + (destY - chicken.view.y) ^ 2)
			local duration = math.max(200, (distance / WANDER_SPEED) * 1000)

			chicken.transitionHandle = transition.to(chicken.view, {
				x = destX,
				y = destY,
				time = duration,
				onComplete = function()
					chicken.transitionHandle = nil
					if not chicken.foodTarget or chicken.foodTarget.removed then
						chicken:setFoodTarget(nil)
						chicken.machine:changeState(decideNextState(chicken))
					elseif chicken.foodTarget.kind == "treat" then
						consumeTreat(chicken)
						chicken.machine:changeState("eatTreat")
					else
						chicken.machine:changeState("eat")
					end
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

	-- Walks to wherever the hen will lay - a bed with an open slot, or a
	-- floor spot near the nearest bed if every bed is full (chicken.layTarget,
	-- set by Chicken:beginNesting). Re-validates on arrival via commitLay,
	-- since the target can go stale (another hen fills the last slot while
	-- this one is still walking) - a stale bed re-decides and re-enters nest
	-- rather than laying somewhere no longer valid (ADR-0013).
	nest = {
		enter = function(chicken)
			local target = chicken.layTarget
			if not target then
				chicken.machine:changeState(decideNextState(chicken))
				return
			end

			chicken:setAnimation("walk")

			local destX, destY
			if target.kind == "bed" then
				destX, destY = target.bed.x, target.bed.y
			else
				destX, destY = target.x, target.y
			end
			-- A bed can sit right at the play area's edge, just outside the
			-- chicken's own (slightly more inset) movement bounds - clamped
			-- the same way pickEatingSpot/pickWanderDestination already are.
			local bounds = getBounds()
			destX = clamp(destX, bounds.minX, bounds.maxX)
			destY = clamp(destY, bounds.minY, bounds.maxY)
			chicken:setFacing(destX < chicken.view.x and -1 or 1)

			local distance = math.sqrt((destX - chicken.view.x) ^ 2 + (destY - chicken.view.y) ^ 2)
			local duration = math.max(200, (distance / WANDER_SPEED) * 1000)

			chicken.transitionHandle = transition.to(chicken.view, {
				x = destX,
				y = destY,
				time = duration,
				onComplete = function()
					chicken.transitionHandle = nil
					local reachedTarget = chicken.layTarget
					chicken.layTarget = nil

					if chicken.layCallbacks.commitLay(reachedTarget, chicken.view.x, chicken.view.y) then
						chicken.gauges:markLaid()
						chicken.machine:changeState(decideNextState(chicken))
						return
					end

					-- The targeted bed filled up while walking - re-decide
					-- from here rather than falling back to the floor outright.
					local freshTarget = chicken.layCallbacks.pickLayTarget(chicken.view.x, chicken.view.y)
					if freshTarget.kind == "immediate" then
						chicken.layCallbacks.commitLay(freshTarget, chicken.view.x, chicken.view.y)
						chicken.gauges:markLaid()
						chicken.machine:changeState(decideNextState(chicken))
					else
						chicken.layTarget = freshTarget
						chicken.machine:changeState("nest")
					end
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

	-- One bout of eating, from a claimed source or foraging. Ends at the
	-- bout's target (finishBout) or when preempted or the source runs out.
	eat = {
		enter = function(chicken)
			chicken:setAnimation("eat")
			chicken.gauges:startBout(chicken.foodTarget ~= nil)
		end,
		exit = function(chicken)
			chicken.gauges:stopEating()
		end,
	},

	-- Plays the eat animation for a fixed duration after finishing a mealworm.
	eatTreat = {
		enter = function(chicken)
			chicken:setAnimation("eat")
			chicken.eatTreatTimerHandle = Clock.after(TREAT_EAT_DURATION, function()
				chicken.eatTreatTimerHandle = nil
				chicken.machine:changeState(decideNextState(chicken))
			end)
		end,
		exit = function(chicken)
			Clock.cancel(chicken.eatTreatTimerHandle)
			chicken.eatTreatTimerHandle = nil
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
			-- Being picked up releases any food target/claim and abandons an
			-- in-progress nest walk.
			chicken:setFoodTarget(nil)
			chicken:cancelNesting()
			chicken:startWiggle()
		end,
		exit = function(chicken)
			chicken:stopWiggle()
		end,
	},
}

return Chicken
