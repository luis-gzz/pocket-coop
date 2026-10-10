local StateMachine = require("src.util.state_machine")
local Constants = require("src.util.constants")
local Layout = require("src.ui.layout")
local YSort = require("src.systems.y_sort")
local Gauges = require("src.objects.chicken.gauges")
local Clock = require("src.systems.clock")
local Tuning = require("src.systems.tuning")
local Feed = require("src.systems.feed")
local Treats = require("src.systems.treats")
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

-- Placeholder until chickens can be named.
local NAME = "Pollo"
local HAPPINESS_ICON = "assets/fauna/heart.png"
local FULLNESS_ICON = "assets/objects/carrot.png"
local CLEANLINESS_ICON = "assets/objects/sparkle.png"
local HYDRATION_ICON = "assets/objects/water_drop.png"

local IDLE_DWELL = { min = 2, max = 4 } -- sim-seconds
local IDLE_WANDER_SPLIT = 0.4 -- probability of idle vs wander when not eating
local WANDER_MIN_RADIUS = 20
local WANDER_MAX_RADIUS = 60
local WANDER_SPEED = 40 -- points per second

-- Beak tip's forward offset from sprite center in the head-down eat frames.
local BEAK_DX = 3.5 * DISPLAY_SCALE
local PECK_PICK_ATTEMPTS = 5

local WIGGLE_ANGLE = 8
local WIGGLE_STEP_TIME = 90
local LONG_PRESS_TIME = 350 -- ms; shorter touches open the tooltip instead

-- How long a chicken plays the eat animation after finishing a mealworm.
local TREAT_EAT_DURATION = 2 -- sim-seconds
local BATHE_DURATION = 4 -- sim-seconds
-- Where a bathing chicken's feet land, below the ash patch's center.
local BATHE_FEET_DY = 2 * DISPLAY_SCALE

-- Shimmy: gentler and quicker than the held wiggle; shift is in native px.
local SHIMMY_ANGLE = 4
local SHIMMY_SHIFT = 1
local SHIMMY_STEP_TIME = 60

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

local WANDER_PICK_ATTEMPTS = 10

-- Retries rather than clamps: clamping an off-area point pins it to the edge,
-- so a chicken already there walks in place. Falls back to heading inward.
local function pickWanderDestination(chicken)
	local bounds = getBounds()
	local fromX, fromY = chicken.view.x, chicken.view.y
	for _ = 1, WANDER_PICK_ATTEMPTS do
		local angle = math.random() * math.pi * 2
		local radius = math.random(WANDER_MIN_RADIUS, WANDER_MAX_RADIUS)
		local x = fromX + math.cos(angle) * radius
		local y = fromY + math.sin(angle) * radius
		if x >= bounds.minX and x <= bounds.maxX and y >= bounds.minY and y <= bounds.maxY then
			return x, y
		end
	end

	local angle = math.atan2((bounds.minY + bounds.maxY) / 2 - fromY, (bounds.minX + bounds.maxX) / 2 - fromX)
	local radius = math.random(WANDER_MIN_RADIUS, WANDER_MAX_RADIUS)
	local x = clamp(fromX + math.cos(angle) * radius, bounds.minX, bounds.maxX)
	local y = clamp(fromY + math.sin(angle) * radius, bounds.minY, bounds.maxY)
	return x, y
end

-- Where to stand so the beak lands on a peck point, feet level with it:
-- whichever side is the shorter walk and in bounds. Returns x, y, facing, point.
local function pickStandSpot(chicken, target)
	local bounds = getBounds()
	local fromX, fromY = chicken.view.x, chicken.view.y
	local point
	for _ = 1, PECK_PICK_ATTEMPTS do
		point = target.pickPeckPoint()
		local y = point.y - GROUND_OFFSET
		local bestX, bestFacing, bestDistance
		for _, facing in ipairs({ 1, -1 }) do
			local x = point.x - facing * BEAK_DX
			local distance = (x - fromX) ^ 2 + (y - fromY) ^ 2
			local inBounds = x >= bounds.minX and x <= bounds.maxX and y >= bounds.minY and y <= bounds.maxY
			if inBounds and (not bestDistance or distance < bestDistance) then
				bestX, bestFacing, bestDistance = x, facing, distance
			end
		end
		if bestX then
			return bestX, y, bestFacing, point
		end
	end
	local x = clamp(point.x - BEAK_DX, bounds.minX, bounds.maxX)
	local y = clamp(point.y - GROUND_OFFSET, bounds.minY, bounds.maxY)
	return x, y, (point.x < x) and -1 or 1, point
end

-- Walks to (destX, destY), then faces arriveFacing (if given) and calls onArrive.
local function walkTo(chicken, destX, destY, arriveFacing, onArrive)
	chicken:setAnimation("walk")
	chicken:setFacing(destX < chicken.view.x and -1 or 1)

	local distance = math.sqrt((destX - chicken.view.x) ^ 2 + (destY - chicken.view.y) ^ 2)
	local duration = math.max(200, (distance / WANDER_SPEED) * 1000)

	chicken.transitionHandle = transition.to(chicken.view, {
		x = destX,
		y = destY,
		time = duration,
		onComplete = function()
			chicken.transitionHandle = nil
			if arriveFacing then
				chicken:setFacing(arriveFacing)
			end
			onArrive()
		end,
	})
end

-- Walks to a stand spot, then faces the peck point and calls onArrive.
local function walkToPeck(chicken, target, onArrive)
	local destX, destY, peckFacing, point = pickStandSpot(chicken, target)
	chicken.peckPoint = point
	walkTo(chicken, destX, destY, peckFacing, onArrive)
end

-- Walks onto an ash patch's center, feet just below it.
local function walkToBath(chicken, target, onArrive)
	local bounds = getBounds()
	local destX = clamp(target.x, bounds.minX, bounds.maxX)
	local destY = clamp(target.y + BATHE_FEET_DY - GROUND_OFFSET, bounds.minY, bounds.maxY)
	walkTo(chicken, destX, destY, nil, onArrive)
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
			chicken:setTarget(target)
			return "approach"
		end
	elseif mode == "forage" then
		chicken:setTarget(nil)
		return "eat"
	end
	return nil
end

local function decideNextState(chicken)
	local hungerState = pickHungerState(chicken)
	if hungerState then
		return hungerState
	end

	chicken:setTarget(nil)
	return (math.random() < IDLE_WANDER_SPLIT) and "idle" or "wander"
end

-- Ends a bout of eating. A food cycle that isn't finished yet (satiety still
-- short of 100) takes a short sim-time break before the next bout.
local function finishBout(chicken)
	chicken:setTarget(nil)
	if chicken.gauges:isHungry() then
		chicken:startBoutBreak()
	end
	chicken.machine:changeState(decideNextState(chicken))
end

-- Applies the treat's payoff and removes it - called once "eatTreat" or
-- "bathe" finishes, so the treat stays visible while in use.
local function consumeTreat(chicken)
	local target = chicken.target
	if target.gauge == "satiety" then
		chicken.gauges:applySatiety(target.amount)
	else
		chicken.gauges:applyCleanliness(target.amount)
	end
	chicken.gauges:applyHappinessBuff()
	Treats.consume(target)
	chicken:setTarget(nil)
end

-- loopCount: 0 (default) loops forever; 1 plays once and holds the last frame.
local function buildSprite(path, numFrames, frameTime, loopCount)
	local sheet = graphics.newImageSheet(path, {
		width = SPRITE_SIZE,
		height = SPRITE_SIZE,
		numFrames = numFrames,
		sheetContentWidth = SPRITE_SIZE * numFrames,
		sheetContentHeight = SPRITE_SIZE,
	})
	local sequenceData = { name = "play", start = 1, count = numFrames, time = frameTime, loopCount = loopCount or 0 }
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
	-- Clamped in case the save came from a different layout or screen size.
	local spawnX = (saved and saved.x) or (spawnBounds.minX + spawnBounds.maxX) / 2
	local spawnY = (saved and saved.y) or (spawnBounds.minY + spawnBounds.maxY) / 2
	self.view.x = clamp(spawnX, spawnBounds.minX, spawnBounds.maxX)
	self.view.y = clamp(spawnY, spawnBounds.minY, spawnBounds.maxY)
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
		sit = buildSprite(SHEET_PATH .. "Sitting/" .. COLOR .. "ChickenSitting-Sheet.png", 4, 400, 1),
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

-- Purely visual - a selected chicken keeps doing whatever it was doing.
function Chicken:setSelected(value)
	self.selected = value
	self.selectedIndicator.isVisible = value
end

-- Abandons an in-progress walk to lay, letting lay progress fire again
-- (ADR-0013) - called wherever a food target is also abandoned, since an
-- interrupted walk means the hen never actually reached its target. Without
-- this, gauges.pendingLay would stay set forever and the hen could never lay
-- again.
function Chicken:cancelNesting()
	self.layTarget = nil
	self.layDeferred = false
	self.gauges.pendingLay = false
end

function Chicken:hasTreat()
	return self.target ~= nil and self.target.kind == "treat"
end

-- target: one of Garden.pickLayTarget's results. "immediate" lays right
-- where the hen stands (no beds exist anywhere); anything else walks there
-- first via the "nest" state. Preempts whatever the hen was doing, except a
-- claimed treat: the lay waits until it's finished (see update).
function Chicken:beginNesting(target)
	if self:hasTreat() then
		self.layDeferred = true
		return
	end
	self:setTarget(nil)
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
	self:setTarget(nil)
	self:cancelNesting()
	self:cancelBoutBreak()
	self.gauges:resetHunger()
	if self.machine.name ~= "held" then
		self.machine:changeState("idle")
	end
end

-- Releases a superseded treat's claim before adopting a new target.
function Chicken:setTarget(newTarget)
	local old = self.target
	if old and old ~= newTarget and old.kind == "treat" then
		Treats.releaseClaim(old)
	end
	self.target = newTarget
end

-- Gives up a treat the player just picked up; the treat alert re-claims
-- one once it's placed again.
function Chicken:abandonTarget()
	self:setTarget(nil)
	local state = self.machine.name
	if state == "approach" or state == "eatTreat" or state == "bathe" then
		self.machine:changeState(decideNextState(self))
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
	if self.machine.name == "eat" and self.target and delivered > 0 then
		if not Feed.deplete(self.target, delivered) then
			self:setTarget(nil)
			self.machine:changeState(decideNextState(self))
		end
	end

	if self.machine.name == "eat" and boutDone then
		finishBout(self)
	end

	-- Hops to another seed when the pecked one runs out; same bout, still eating.
	local target = self.target
	if self.machine.name == "eat" and target and target.hasPeckPoint and not self.transitionHandle
		and not target.hasPeckPoint(self.peckPoint) then
		walkToPeck(self, target, function()
			self:setAnimation("eat")
		end)
	end

	-- Hunger is acted on here, not at the next re-decide, so high time scale
	-- can't overshoot it. Interrupts idle/wander, or foraging once food appears.
	local state = self.machine.name
	local isForaging = state == "eat" and not self.target
	local interruptible = state == "idle" or state == "wander"
		or (isForaging and self.gauges:getHungerMode() == "food")
	if interruptible then
		local hungerState = pickHungerState(self)
		if hungerState then
			self.machine:changeState(hungerState)
		end
	end

	-- A treat alert is checked every frame and preempts whatever the
	-- chicken is doing, including a nest walk - except while held or
	-- already committed to a claimed treat (ADR-0018).
	if self.machine.name ~= "held" and not self:hasTreat() then
		local gauges = self.gauges
		local claimed = Treats.claimNear(self, self.view.x, self.view.y, gauges.satiety, gauges.cleanliness)
		if claimed then
			self:cancelNesting()
			self:setTarget(claimed)
			self.machine:changeState("approach")
		elseif self.layDeferred then
			-- The treat that held up a lay is done; go lay now.
			self.layDeferred = false
			self:beginNesting(self.layCallbacks.pickLayTarget(self.view.x, self.view.y))
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
		local view = self.view
		self.dragOffsetX = view.x - x
		self.dragOffsetY = view.y - y
		self.machine:changeState("held")
	end

	local function isOverChicken(x, y)
		local bounds = hitArea.contentBounds
		return x >= bounds.xMin and x <= bounds.xMax and y >= bounds.yMin and y <= bounds.yMax
	end

	-- Drops a touch that left the chicken before pickup: no pickup, no tooltip.
	local function cancelPendingTouch()
		if self.longPressHandle then
			timer.cancel(self.longPressHandle)
			self.longPressHandle = nil
		end
		self.pendingTouch = nil
		display.getCurrentStage():setFocus(hitArea, nil)
		hitArea.isFocus = false
	end

	local lastX, lastY

	local function onTouch(event)
		if event.phase == "began" then
			display.getCurrentStage():setFocus(hitArea, event.id)
			hitArea.isFocus = true
			self.pendingTouch = true
			lastX, lastY = event.x, event.y
			self.longPressHandle = timer.performWithDelay(LONG_PRESS_TIME, function()
				self.longPressHandle = nil
				if not self.pendingTouch then
					return
				end
				-- The chicken may have walked out from under a still finger.
				if not isOverChicken(lastX, lastY) then
					cancelPendingTouch()
					return
				end
				beginHeld(lastX, lastY)
				self.pendingTouch = nil
			end)
		elseif hitArea.isFocus then
			if event.phase == "moved" then
				lastX, lastY = event.x, event.y
				if self.pendingTouch and not isOverChicken(event.x, event.y) then
					cancelPendingTouch()
				elseif self.machine.name == "held" then
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
							corner = true,
							title = NAME,
							onShow = function()
								self:setSelected(true)
							end,
							onHide = function()
								self:setSelected(false)
							end,
							rows = {
								{ icon = HAPPINESS_ICON, getValue = function() return self.gauges:getHappiness() end },
								{ icon = FULLNESS_ICON, getValue = function() return self.gauges.satiety end },
								{ icon = CLEANLINESS_ICON, getValue = function() return self.gauges.cleanliness end },
								{ icon = HYDRATION_ICON, getValue = function() return self.gauges.hydration end },
							},
						})
					end
				elseif self.machine.name == "held" then
					-- Releasing in place synthesizes a tap; don't let it close the tooltip.
					Tooltip.ignoreNextTap()
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

-- The bathe state's shimmy: rocks and nudges the body side to side until
-- stopped. Body-local units, so the shift is in native pixels.
function Chicken:startShimmy()
	local direction = 1
	local function step()
		self.shimmyHandle = transition.to(self.body, {
			rotation = SHIMMY_ANGLE * direction,
			x = SHIMMY_SHIFT * direction,
			time = SHIMMY_STEP_TIME,
			onComplete = step,
		})
		direction = -direction
	end
	step()
end

function Chicken:stopShimmy()
	if self.shimmyHandle then
		transition.cancel(self.shimmyHandle)
		self.shimmyHandle = nil
	end
	self.body.rotation = 0
	self.body.x = 0
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

	-- Walks to a claimed source or treat; arrival hands off to "eat" for a
	-- source, "eatTreat" for a mealworm, or "bathe" for ash.
	approach = {
		enter = function(chicken)
			local target = chicken.target
			if not target or target.removed then
				chicken:setTarget(nil)
				chicken.machine:changeState(decideNextState(chicken))
				return
			end

			local isBath = target.type == "ash"
			local walk = isBath and walkToBath or walkToPeck
			walk(chicken, target, function()
				if not chicken.target or chicken.target.removed then
					chicken:setTarget(nil)
					chicken.machine:changeState(decideNextState(chicken))
				elseif isBath then
					chicken.machine:changeState("bathe")
				elseif chicken.target.kind == "treat" then
					chicken.machine:changeState("eatTreat")
				else
					chicken.machine:changeState("eat")
				end
			end)
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
			-- the same way pickStandSpot/pickWanderDestination already are.
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
			chicken.gauges:startBout(chicken.target ~= nil)
		end,
		exit = function(chicken)
			if chicken.transitionHandle then
				transition.cancel(chicken.transitionHandle)
				chicken.transitionHandle = nil
			end
			chicken.gauges:stopEating()
		end,
	},

	-- Plays the eat animation over a claimed treat for a fixed duration,
	-- then consumes it.
	eatTreat = {
		enter = function(chicken)
			chicken:setAnimation("eat")
			chicken.eatTreatTimerHandle = Clock.after(TREAT_EAT_DURATION, function()
				chicken.eatTreatTimerHandle = nil
				if chicken.target and not chicken.target.removed then
					consumeTreat(chicken)
				end
				chicken.machine:changeState(decideNextState(chicken))
			end)
		end,
		exit = function(chicken)
			Clock.cancel(chicken.eatTreatTimerHandle)
			chicken.eatTreatTimerHandle = nil
		end,
	},

	-- Sits on claimed ash and shimmies for a fixed duration, then
	-- consumes it. Picking the chicken up cancels with no payoff.
	bathe = {
		enter = function(chicken)
			chicken:setAnimation("sit")
			chicken:startShimmy()
			chicken.batheTimerHandle = Clock.after(BATHE_DURATION, function()
				chicken.batheTimerHandle = nil
				if chicken.target and not chicken.target.removed then
					consumeTreat(chicken)
				end
				chicken.machine:changeState(decideNextState(chicken))
			end)
		end,
		exit = function(chicken)
			Clock.cancel(chicken.batheTimerHandle)
			chicken.batheTimerHandle = nil
			chicken:stopShimmy()
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
			chicken:setTarget(nil)
			chicken:cancelNesting()
			chicken:startWiggle()
		end,
		exit = function(chicken)
			chicken:stopWiggle()
		end,
	},
}

return Chicken
