local StateMachine = require("src.util.state_machine")
local Constants = require("src.util.constants")
local Layout = require("src.ui.layout")
local YSort = require("src.systems.y_sort")
local Gauges = require("src.objects.chicken.gauges")
local Clock = require("src.systems.clock")
local Tuning = require("src.systems.tuning")
local Feed = require("src.systems.feed")
local Treats = require("src.systems.treats")
local Bowls = require("src.systems.bowls")
local Tooltip = require("src.ui.tooltip")
local HappinessIcon = require("src.ui.happiness_icon")
local Wiggle = require("src.util.wiggle")
local Shadow = require("src.objects.shadow")
local WanderRoute = require("src.util.wander_route")
local Footprints = require("src.systems.footprints")

local Chicken = {}
Chicken.__index = Chicken

local SPRITE_SIZE = 16
-- Shared with the ground tiles so pixel density matches across all art.
local DISPLAY_SCALE = Constants.PIXEL_SCALE
local SHEET_PATH = "assets/fauna/CHICKEN/"
local COLOR = "LightBrown"

-- The selected ring's size, matching the shadow beneath it.
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
local FULLNESS_ICON = "assets/objects/carrot.png"
local CLEANLINESS_ICON = "assets/objects/sparkle.png"
local HYDRATION_ICON = "assets/objects/water_drop.png"

local IDLE_DWELL = { min = 2, max = 4 } -- sim-seconds
local IDLE_WANDER_SPLIT = 0.4 -- probability of idle vs wander when not eating
local WANDER_SPEED = 40 -- points per second
-- Wander eases between this fraction of full speed and full over the ramp distance.
local WANDER_RAMP_MIN = 0.3
local WANDER_RAMP_DISTANCE = 10
-- How far horizontal travel must point the other way before the sprite flips.
local FACING_DEADZONE = 0.25

-- Beak tip's forward offset from sprite center in the head-down eat frames.
local BEAK_DX = 3.5 * DISPLAY_SCALE
-- Drinking aims the beak into water, not at her feet: its height above them.
local DRINK_BEAK_DY = 2.5 * DISPLAY_SCALE
local PECK_PICK_ATTEMPTS = 5

local WIGGLE_ANGLE = 8
local WIGGLE_STEP_TIME = 90
local LONG_PRESS_TIME = 350 -- ms; shorter touches open the tooltip instead

-- Drink: the eat sheet's head-down dip once, sips between frames 5 and 6,
-- then raises its head (5 back to 1) once it's done.
local DRINK_DIP_TIME = 580 -- ms, frames 1-5
local DRINK_SIP_TIME = 800 -- ms per 5-6 cycle

-- How long a chicken plays the eat animation after finishing a mealworm.
local TREAT_EAT_DURATION = 2 -- sim-seconds
local BATHE_DURATION = 4 -- sim-seconds
-- Where a bathing chicken's feet land, below the ash patch's center.
local BATHE_FEET_DY = 2 * DISPLAY_SCALE

-- Shimmy: gentler and quicker than the held wiggle; shift is in native px.
local SHIMMY_ANGLE = 4
local SHIMMY_SHIFT = 1
local SHIMMY_STEP_TIME = 60

-- Footprint clearance (ADR-0021): her body stays this far off a fixture's
-- sides; only her feet count vertically. Detour corners sit a little further
-- out so rounding them doesn't cut back in.
local CLEARANCE_X = 6 * DISPLAY_SCALE
local CLEARANCE_Y = 1 * DISPLAY_SCALE
local CORNER_MARGIN = 3 * DISPLAY_SCALE
local SPOT_ATTEMPTS = 10

-- Nest: she hops onto a bed from just off its side, feet this far below
-- its center, and sits this long before laying.
local BED_EDGE_GAP = 3 * DISPLAY_SCALE
local BED_STAND_DY = 2 * DISPLAY_SCALE
local HOP_TIME = 0.45 -- seconds
local HOP_HEIGHT = 6 -- native px (the body is in view-local units)
local SETTLE_DURATION = 2 -- sim-seconds

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

-- Footprint queries in view coordinates: footprints work in feet y.
local function isBlocked(x, y)
	return Footprints.findAt(x, y + GROUND_OFFSET, CLEARANCE_X, CLEARANCE_Y) ~= nil
end

local function pushOutOfFootprints(x, y)
	local pushedX, pushedY = Footprints.pushOut(x, y + GROUND_OFFSET, CLEARANCE_X, CLEARANCE_Y)
	return pushedX, pushedY - GROUND_OFFSET
end

-- Corner points of a walk around every footprint, in view coordinates.
local function findDetour(fromX, fromY, toX, toY)
	local bounds = getBounds()
	local points = Footprints.findPath(fromX, fromY + GROUND_OFFSET, toX, toY + GROUND_OFFSET, {
		padX = CLEARANCE_X,
		padY = CLEARANCE_Y,
		margin = CORNER_MARGIN,
		bounds = {
			minX = bounds.minX,
			maxX = bounds.maxX,
			minY = bounds.minY + GROUND_OFFSET,
			maxY = bounds.maxY + GROUND_OFFSET,
		},
	})
	for _, point in ipairs(points) do
		point.y = point.y - GROUND_OFFSET
	end
	return points
end

local WANDER_AVOID = { blocked = isBlocked, pushOut = pushOutOfFootprints, detour = findDetour }

-- Where to stand so the beak lands on a peck point, feet level with it:
-- whichever side is the shorter walk, in bounds, and clear of footprints
-- (unless the target is the fixture being used). The target picks a point
-- for each side's facing. Returns x, y, facing, point.
local function pickStandSpot(chicken, target)
	local isBowl = target.kind == "bowl"
	local reachY = isBowl and DRINK_BEAK_DY or 0
	local bounds = getBounds()
	local fromX, fromY = chicken.view.x, chicken.view.y
	local point
	for _ = 1, PECK_PICK_ATTEMPTS do
		local bestX, bestY, bestFacing, bestPoint, bestDistance
		for _, facing in ipairs({ 1, -1 }) do
			point = target.pickPeckPoint(facing)
			local x = point.x - facing * BEAK_DX
			local y = point.y + reachY - GROUND_OFFSET
			local distance = (x - fromX) ^ 2 + (y - fromY) ^ 2
			local inBounds = x >= bounds.minX and x <= bounds.maxX and y >= bounds.minY and y <= bounds.maxY
				and (isBowl or not isBlocked(x, y))
			if inBounds and (not bestDistance or distance < bestDistance) then
				bestX, bestY, bestFacing, bestPoint, bestDistance = x, y, facing, point, distance
			end
		end
		if bestX then
			return bestX, bestY, bestFacing, bestPoint
		end
	end
	local x = clamp(point.x - BEAK_DX, bounds.minX, bounds.maxX)
	local y = clamp(point.y + reachY - GROUND_OFFSET, bounds.minY, bounds.maxY)
	return x, y, (point.x < x) and -1 or 1, point
end

-- Walks to (destX, destY) around footprints, then faces arriveFacing (if
-- given) and calls onArrive. Stepped in update; stopWalk() abandons it.
local function walkTo(chicken, destX, destY, arriveFacing, onArrive)
	chicken:setAnimation("walk")
	chicken:setFacing(destX < chicken.view.x and -1 or 1)
	chicken.walk = {
		route = WanderRoute.fromPoints(findDetour(chicken.view.x, chicken.view.y, destX, destY)),
		distance = 0,
		destX = destX,
		destY = destY,
		arriveFacing = arriveFacing,
		onArrive = onArrive,
	}
end

local function stepWalk(chicken, realDt)
	local walk = chicken.walk
	walk.distance = math.min(walk.route.total, walk.distance + WANDER_SPEED * realDt)
	local x, y, dirX = WanderRoute.sample(walk.route, walk.distance)
	chicken.view.x, chicken.view.y = x, y
	if math.abs(dirX) > FACING_DEADZONE then
		chicken:setFacing(dirX < 0 and -1 or 1)
	end
	if walk.distance >= walk.route.total then
		chicken.walk = nil
		if walk.arriveFacing then
			chicken:setFacing(walk.arriveFacing)
		end
		walk.onArrive()
	end
end

-- Hops in an arc to (destX, destY), then calls onLand. Stepped in update.
local function hopTo(chicken, destX, destY, onLand)
	chicken:setAnimation("walk")
	chicken:setFacing(destX < chicken.view.x and -1 or (destX > chicken.view.x and 1 or 0))
	chicken.hop = { fromX = chicken.view.x, fromY = chicken.view.y, toX = destX, toY = destY, elapsed = 0, onLand = onLand }
end

local function stepHop(chicken, realDt)
	local hop = chicken.hop
	hop.elapsed = hop.elapsed + realDt
	local t = math.min(1, hop.elapsed / HOP_TIME)
	chicken.view.x = hop.fromX + (hop.toX - hop.fromX) * t
	chicken.view.y = hop.fromY + (hop.toY - hop.fromY) * t
	chicken.body.y = -math.sin(math.pi * t) * HOP_HEIGHT
	if t >= 1 then
		chicken.hop = nil
		chicken.body.y = 0
		hop.onLand()
	end
end

-- Just off one side of a bed (side -1 or 1), feet midway down its footprint.
local function bedSideSpot(bed, side)
	local rect = Footprints.rect(bed)
	return bed.x + side * (bed.width / 2 + BED_EDGE_GAP), (rect.minY + rect.maxY) / 2 - GROUND_OFFSET
end

-- The side nearer (x), unless it's out of bounds or blocked by another fixture.
local function pickBedSide(bed, x)
	local bounds = getBounds()
	local preferred = (x < bed.x) and -1 or 1
	for _, side in ipairs({ preferred, -preferred }) do
		local spotX, spotY = bedSideSpot(bed, side)
		local clear = Footprints.findAt(spotX, spotY + GROUND_OFFSET, CLEARANCE_X, CLEARANCE_Y, bed) == nil
		if spotX >= bounds.minX and spotX <= bounds.maxX and clear then
			return side
		end
	end
	return preferred
end

-- Walks to a stand spot, then faces the peck point and calls onArrive.
local function walkToPeck(chicken, target, onArrive)
	local destX, destY, peckFacing, point = pickStandSpot(chicken, target)
	chicken.peckPoint = point
	if target.claimPeckPoint then
		target.claimPeckPoint(point)
	end
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

-- "approach" to the nearest bowl with water while thirsty, else nil.
local function pickThirstState(chicken)
	if not chicken.gauges:isThirsty() then
		return nil
	end
	local bowl = Bowls.findNearestWithWater(chicken.view.x, chicken.view.y)
	if bowl then
		chicken:setTarget(bowl)
		return "approach"
	end
	return nil
end

-- Hunger or thirst, whichever gauge is lower first when both are open.
local function pickNeedState(chicken)
	local gauges = chicken.gauges
	if gauges.satiety <= gauges.hydration then
		return pickHungerState(chicken) or pickThirstState(chicken)
	end
	return pickThirstState(chicken) or pickHungerState(chicken)
end

local function decideNextState(chicken)
	local needState = pickNeedState(chicken)
	if needState then
		return needState
	end

	chicken:setTarget(nil)
	return (math.random() < IDLE_WANDER_SPLIT) and "idle" or "wander"
end

-- Picks the next state at a wander route's end: hunger/thirst first, then
-- the idle/wander roll made when the route was planned.
local function finishWander(chicken)
	local route = chicken.wanderRoute
	local needState = pickNeedState(chicken)
	if needState then
		chicken.machine:changeState(needState)
	elseif route.chains then
		chicken.continueHeading = route.endHeading
		chicken.machine:changeState("wander")
	else
		chicken.machine:changeState("idle")
	end
end

-- Advances along the wander route by real time, easing at whichever ends stop.
local function stepWander(chicken, realDt)
	local route = chicken.wanderRoute
	local ramp = 1
	if route.easeIn then
		ramp = math.min(ramp, chicken.wanderDistance / WANDER_RAMP_DISTANCE)
	end
	if route.easeOut then
		ramp = math.min(ramp, (route.total - chicken.wanderDistance) / WANDER_RAMP_DISTANCE)
	end
	ramp = WANDER_RAMP_MIN + (1 - WANDER_RAMP_MIN) * clamp(ramp, 0, 1)

	chicken.wanderDistance = math.min(route.total, chicken.wanderDistance + WANDER_SPEED * ramp * realDt)
	local x, y, dirX = WanderRoute.sample(route, chicken.wanderDistance)
	chicken.view.x, chicken.view.y = x, y
	if math.abs(dirX) > FACING_DEADZONE then
		chicken:setFacing(dirX < 0 and -1 or 1)
	end

	if chicken.wanderDistance >= route.total then
		finishWander(chicken)
	end
end

-- Thin debug-only line along a wander or walk route.
local function drawRoute(route)
	local xs, ys = route.xs, route.ys
	if #xs < 2 then
		return nil
	end
	local line = display.newLine(YSort.getGroup(), xs[1], ys[1], xs[2], ys[2])
	for i = 3, #xs do
		line:append(xs[i], ys[i])
	end
	line.strokeWidth = 1
	line:setStrokeColor(1, 0.2, 0.2, 0.8)
	return line
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
	elseif target.gauge == "hydration" then
		chicken.gauges:applyHydration(target.amount)
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

-- The eat sheet as a drink: dips once, then loops the head-down sip until
-- "rise" plays, which calls sprite.onRaised when the head is back up.
local function buildDrinkSprite(path)
	local sheet = graphics.newImageSheet(path, {
		width = SPRITE_SIZE,
		height = SPRITE_SIZE,
		numFrames = 6,
		sheetContentWidth = SPRITE_SIZE * 6,
		sheetContentHeight = SPRITE_SIZE,
	})
	local sprite = display.newSprite(sheet, {
		{ name = "dip", start = 1, count = 5, time = DRINK_DIP_TIME, loopCount = 1 },
		{ name = "sip", frames = { 5, 6 }, time = DRINK_SIP_TIME, loopCount = 0 },
		{ name = "rise", frames = { 5, 4, 3, 2, 1 }, time = DRINK_DIP_TIME, loopCount = 1 },
	})
	sprite.firstSequence = "dip"
	sprite:addEventListener("sprite", function(event)
		if event.phase == "ended" and event.target.sequence == "dip" then
			event.target:setSequence("sip")
			event.target:play()
		elseif event.phase == "ended" and event.target.sequence == "rise" and sprite.onRaised then
			sprite.onRaised()
		end
	end)
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
	-- Standing on a hen bed, she draws in front of it and its eggs.
	YSort.add(self.view, function(view)
		local depth = view.y + GROUND_OFFSET
		if self.mountedBed then
			depth = math.max(depth, self.mountedBed.y + self.mountedBed.height / 2 + 1)
		end
		return depth
	end)

	-- view is already scaled by DISPLAY_SCALE, so the shadow's unit is 1.
	Shadow.newOval(self.view, SPRITE_SIZE, 1).y = SPRITE_SIZE / 2

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
		drink = buildDrinkSprite(SHEET_PATH .. "Eating/" .. COLOR .. "ChickenEating-Sheet.png"),
		sit = buildSprite(SHEET_PATH .. "Sitting/" .. COLOR .. "ChickenSitting-Sheet.png", 4, 400, 1),
	}
	for _, sprite in pairs(self.sprites) do
		self.body:insert(sprite)
	end

	self:setupTouch()
	self:teleportTo(pushOutOfFootprints(self.view.x, self.view.y))
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
	if sprite.firstSequence then
		sprite:setSequence(sprite.firstSequence)
	end
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
	self.gauges:resetThirst()
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

-- A random point within the chicken's movement bounds and clear of
-- footprints, where it reappears after offline catch-up.
function Chicken.randomSpot()
	local bounds = getBounds()
	local x, y
	for _ = 1, SPOT_ATTEMPTS do
		x = bounds.minX + math.random() * (bounds.maxX - bounds.minX)
		y = bounds.minY + math.random() * (bounds.maxY - bounds.minY)
		if not isBlocked(x, y) then
			break
		end
	end
	return x, y
end

-- Debug: whether every chicken draws the route it's following.
Chicken.showRoutes = false

function Chicken.setShowRoutes(value)
	Chicken.showRoutes = value
end

-- Keeps the debug route line in step with whichever route she's on.
function Chicken:updateRouteLine()
	local route = Chicken.showRoutes and (self.wanderRoute or (self.walk and self.walk.route)) or nil
	if route == self.routeLineFor then
		return
	end
	if self.routeLine then
		self.routeLine:removeSelf()
		self.routeLine = nil
	end
	self.routeLineFor = route
	if route then
		self.routeLine = drawRoute(route)
	end
end

function Chicken:stopWalk()
	self.walk = nil
end

function Chicken:stopHop()
	self.hop = nil
	self.body.y = 0
end

function Chicken:mount(bed)
	self.mountedBed = bed
	bed.occupant = self
end

function Chicken:dismount()
	if self.mountedBed and self.mountedBed.occupant == self then
		self.mountedBed.occupant = nil
	end
	self.mountedBed = nil
end

-- The lay target went stale on arrival: lays at once if no bed exists now,
-- otherwise heads for a fresh target.
function Chicken:retargetLay()
	local freshTarget = self.layCallbacks.pickLayTarget(self.view.x, self.view.y)
	if freshTarget.kind == "immediate" then
		self.layTarget = freshTarget
		self:layAndMoveOn()
	else
		self.layTarget = freshTarget
		self.machine:changeState("nest")
	end
end

-- Lays where she stands (a floor spot, or no bed at all), then re-decides.
function Chicken:layAndMoveOn()
	if self.layCallbacks.commitLay(self.layTarget, self.view.x, self.view.y) then
		self.layTarget = nil
		self.gauges:markLaid()
		self.machine:changeState(decideNextState(self))
	else
		self:retargetLay()
	end
end

-- Lays into the bed she's sitting on and hops off toward her next
-- destination (the side she came up, if it has none). A bed that filled up
-- meanwhile sends her back down to look again.
function Chicken:layAndHopOff(bed, cameSide)
	if not self.layCallbacks.commitLay(self.layTarget, self.view.x, self.view.y) then
		hopTo(self, bedSideSpot(bed, cameSide))
		self.hop.onLand = function()
			self:dismount()
			self:retargetLay()
		end
		return
	end
	self.layTarget = nil
	self.gauges:markLaid()

	local nextState = decideNextState(self)
	local side = cameSide
	if self.target and self.target.x then
		side = (self.target.x < bed.x) and -1 or 1
	end
	hopTo(self, bedSideSpot(bed, side))
	self.hop.onLand = function()
		self:dismount()
		self.machine:changeState(nextState)
	end
end

-- A bed picked up while she's on it or heading to it: she hops down (or
-- stops) and waits, then heads for it again once it's put down.
function Chicken:followMovedBed()
	local target = self.layTarget
	if self.machine.name ~= "nest" or not target or target.kind ~= "bed" then
		return
	end
	local bed = target.bed
	if bed.dragging and not self.nestWaiting then
		self.nestWaiting = true
		self:stopWalk()
		Clock.cancel(self.settleHandle)
		self.settleHandle = nil
		if self.mountedBed then
			-- record x/y stay put until the drop, so this is where it was.
			self:stopHop()
			hopTo(self, bedSideSpot(bed, pickBedSide(bed, self.view.x)))
			self.hop.onLand = function()
				self:dismount()
				self:setAnimation("idle")
			end
		else
			self:stopHop()
			self:setAnimation("idle")
		end
	elseif self.nestWaiting and not bed.dragging and not self.hop then
		self.layTarget = self.layCallbacks.pickLayTarget(self.view.x, self.view.y)
		self.machine:changeState("nest")
	end
end

-- After a fixture is placed or moved (CONTEXT.md's Footprint): steps out of
-- any footprint she's now inside, and re-plans whatever walk she's on.
function Chicken:leaveFootprints()
	local state = self.machine.name
	if state == "held" or self.mountedBed then
		return
	end
	local exclude = (self.target and self.target.kind == "bowl") and self.target or nil
	local x, y = self.view.x, self.view.y
	local inside = Footprints.findAt(x, y + GROUND_OFFSET, CLEARANCE_X, CLEARANCE_Y, exclude) ~= nil
	if inside then
		local bounds = getBounds()
		x, y = pushOutOfFootprints(x, y)
		self:teleportTo(clamp(x, bounds.minX, bounds.maxX), clamp(y, bounds.minY, bounds.maxY))
	end

	if state == "wander" then
		self.machine:changeState("wander")
	elseif self.walk then
		local walk = self.walk
		walkTo(self, walk.destX, walk.destY, walk.arriveFacing, walk.onArrive)
	elseif inside and state == "nest" then
		self.machine:changeState("nest")
	elseif inside and state ~= "idle" then
		self:setTarget(nil)
		self.machine:changeState(decideNextState(self))
	end
end

-- Moves the chicken instantly, hit target included. Callers stop any walk
-- first (resetForCatchUp does).
function Chicken:teleportTo(x, y)
	self.view.x, self.view.y = x, y
	self.hitArea.x, self.hitArea.y = x, y
end

-- Driven every frame by garden.lua's own frame loop (not a private listener
-- here - see garden.lua for why): drives the gauges, debits any food source
-- or bowl being eaten or drunk from, and checks for a nearby treat alert. dt is already
-- time-scaled (from Clock); dirt is the garden-wide dropping + floor egg
-- penalty. Returns any newly spawned dropping records and whether a
-- lay happened this call, so Garden can create their views / hatch the egg -
-- both are Garden-owned concerns now, not this chicken's.
function Chicken:update(dt, dirt, hasSource, hasWater)
	if self.machine.name == "wander" then
		stepWander(self, Clock.getRawDt())
	elseif self.walk then
		stepWalk(self, Clock.getRawDt())
	end
	if self.hop then
		stepHop(self, Clock.getRawDt())
	end
	self:followMovedBed()
	self:updateRouteLine()

	-- Keeps the hit target glued to the chicken and always frontmost.
	self.hitArea.x = self.view.x
	self.hitArea.y = self.view.y
	self.hitArea:toFront()

	local isHeld = self.machine.name == "held"
	local spawned, laid, delivered, boutDone, drank = self.gauges:update(
		dt, dirt, self.view.x, self.view.y, isHeld, hasSource, hasWater
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

	-- Drinks until full or the bowl runs dry, then raises its head before
	-- moving on. A picked-up bowl is left at once, mid-approach too.
	local state = self.machine.name
	local bowl = self.target
	if (state == "drink" or state == "approach") and bowl and bowl.kind == "bowl" then
		if bowl.dragging then
			self:setTarget(nil)
			self.machine:changeState(decideNextState(self))
		elseif state == "drink" and not self.drinkFinishing
			and (not self.gauges:isThirsty() or (drank > 0 and not Bowls.drain(bowl, drank))) then
			self.drinkFinishing = true
			self.gauges:stopDrinking()
			self.activeSprite:setSequence("rise")
			self.activeSprite:play()
		end
	end

	-- When the pecked seed runs out, pecks a nearby one in place, else hops
	-- to another - same bout, paused until it arrives so no seed goes mid-walk.
	local target = self.target
	if self.machine.name == "eat" and target and target.hasPeckPoint and not self.walk
		and not target.hasPeckPoint(self.peckPoint) then
		local nearby = target.findNearbyPeckPoint and target.findNearbyPeckPoint(self.peckPoint)
		if nearby then
			self.peckPoint = nearby
			target.claimPeckPoint(nearby)
		else
			self.gauges:setEatingPaused(true)
			walkToPeck(self, target, function()
				self.gauges:setEatingPaused(false)
				self:setAnimation("eat")
			end)
		end
	end

	-- Hunger and thirst are acted on here, not at the next re-decide, so high
	-- time scale can't overshoot them. Interrupts idle/wander, or foraging
	-- once food appears or thirst opens.
	state = self.machine.name
	local isForaging = state == "eat" and not self.target
	local interruptible = state == "idle" or state == "wander"
		or (isForaging and (self.gauges:getHungerMode() == "food" or self.gauges:isThirsty()))
	if interruptible then
		local needState = pickNeedState(self)
		if needState and not (isForaging and needState == "eat") then
			self.machine:changeState(needState)
		end
	end

	-- A treat alert is checked every frame and preempts whatever the
	-- chicken is doing, including a nest walk - except while held or
	-- already committed to a claimed treat (ADR-0018).
	if self.machine.name ~= "held" and not self:hasTreat() and not self.mountedBed then
		local gauges = self.gauges
		local claimed = Treats.claimNear(self, self.view.x, self.view.y, gauges)
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
							source = self,
							onShow = function()
								self:setSelected(true)
							end,
							onHide = function()
								self:setSelected(false)
							end,
							rows = {
								{
									icon = HappinessIcon.live(function() return self.gauges:getHappiness() end),
									getValue = function() return self.gauges:getHappiness() end,
								},
								{ icon = FULLNESS_ICON, getValue = function() return self.gauges.satiety end },
								{ icon = CLEANLINESS_ICON, getValue = function() return self.gauges.cleanliness end },
								{ icon = HYDRATION_ICON, getValue = function() return self.gauges.hydration end },
							},
						})
					end
				elseif self.machine.name == "held" then
					-- Releasing in place synthesizes a tap; don't let it close the tooltip.
					Tooltip.ignoreNextTap()
					local bounds = getBounds()
					local x, y = pushOutOfFootprints(self.view.x, self.view.y)
					self:teleportTo(clamp(x, bounds.minX, bounds.maxX), clamp(y, bounds.minY, bounds.maxY))
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

	-- Walks to a claimed source, bowl, or treat; arrival hands off to "eat"
	-- for a source, "drink" for a bowl, "eatTreat" for a mealworm or
	-- watermelon slice, or "bathe" for ash.
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
				elseif chicken.target.kind == "bowl" then
					chicken.machine:changeState("drink")
				elseif chicken.target.kind == "treat" then
					chicken.machine:changeState("eatTreat")
				else
					chicken.machine:changeState("eat")
				end
			end)
		end,
		exit = function(chicken)
			chicken:stopWalk()
		end,
	},

	-- Walks to wherever the hen will lay - a bed with an open slot, or a
	-- floor spot near the nearest bed if every bed is full (chicken.layTarget,
	-- set by Chicken:beginNesting). For a bed she walks around to one side,
	-- hops up over the slot she'll fill, sits a moment, and the egg appears
	-- as she hops off. Re-validates before hopping up and again at the lay,
	-- since the target can go stale (another hen fills the last slot) - a
	-- stale bed re-decides and re-enters nest rather than laying somewhere no
	-- longer valid (ADR-0013).
	nest = {
		enter = function(chicken)
			local target = chicken.layTarget
			if not target then
				chicken.machine:changeState(decideNextState(chicken))
				return
			end

			if target.kind ~= "bed" then
				local bounds = getBounds()
				local destX = clamp(target.x, bounds.minX, bounds.maxX)
				local destY = clamp(target.y, bounds.minY, bounds.maxY)
				walkTo(chicken, destX, destY, nil, function()
					chicken:layAndMoveOn()
				end)
				return
			end

			local bed = target.bed
			local side = pickBedSide(bed, chicken.view.x)
			local sideX, sideY = bedSideSpot(bed, side)
			walkTo(chicken, sideX, sideY, -side, function()
				local slotX = chicken.layCallbacks.getOpenSlotX(bed)
				if not slotX then
					chicken:retargetLay()
					return
				end
				chicken:mount(bed)
				hopTo(chicken, slotX, bed.y + BED_STAND_DY - GROUND_OFFSET, function()
					chicken:setAnimation("sit")
					chicken.settleHandle = Clock.after(SETTLE_DURATION, function()
						chicken.settleHandle = nil
						chicken:layAndHopOff(bed, side)
					end)
				end)
			end)
		end,
		exit = function(chicken)
			chicken:stopWalk()
			chicken:stopHop()
			Clock.cancel(chicken.settleHandle)
			chicken.settleHandle = nil
			chicken.nestWaiting = false
			chicken:dismount()
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
			chicken:stopWalk()
			chicken.gauges:stopEating()
		end,
	},

	-- Drinks from a bowl until full, in one sitting, then raises its head;
	-- update() ends it early if the bowl runs dry or is picked up.
	drink = {
		enter = function(chicken)
			chicken:setAnimation("drink")
			chicken.gauges:startDrinking()
			chicken.sprites.drink.onRaised = function()
				chicken:setTarget(nil)
				chicken.machine:changeState(decideNextState(chicken))
			end
		end,
		exit = function(chicken)
			chicken.sprites.drink.onRaised = nil
			chicken.drinkFinishing = false
			chicken.gauges:stopDrinking()
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

	-- Follows a planned wander route (stepped in update). Rolls up front
	-- whether another wander follows, so a chained route needn't slow down.
	wander = {
		enter = function(chicken)
			local heading = chicken.continueHeading
			chicken.continueHeading = nil
			-- A chained wander keeps the walk cycle going rather than restarting it.
			if chicken.activeSprite ~= chicken.sprites.walk then
				chicken:setAnimation("walk")
			end

			local route = WanderRoute.build(chicken.view.x, chicken.view.y, heading, getBounds(), WANDER_AVOID)
			route.chains = math.random() >= IDLE_WANDER_SPLIT
			route.easeIn = not route.keptHeading
			route.easeOut = not route.chains
			chicken.wanderRoute = route
			chicken.wanderDistance = 0
		end,
		exit = function(chicken)
			chicken.wanderRoute = nil
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
