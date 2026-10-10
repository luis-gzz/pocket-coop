local Constants = require("src.util.constants")
local Placement = require("src.systems.placement")
local Mealworm = require("src.objects.items.mealworm")
local Ash = require("src.objects.items.ash")

-- The shared owner of every placed treat: mealworms and ash
-- (CONTEXT.md's "Treats"). Feed's counterpart for one-use items, owned by
-- Garden alongside it (ADR-0018).
local Treats = {}

-- A treat alerts the nearest chicken within this radius, re-checked every
-- frame.
local ALERT_RADIUS = 48 * Constants.PIXEL_SCALE

-- type -> its item module (WIDTH, HEIGHT, GAUGE, AMOUNT, new).
local TYPES = {
	mealworm = Mealworm,
	ash = Ash,
}

local items = {}
Placement.register(function()
	return items
end)
local onSave = nil

local function save()
	if onSave then
		onSave()
	end
end

function Treats.setSaveCallback(fn)
	onSave = fn
end

local function removeItem(item)
	for index, existing in ipairs(items) do
		if existing == item then
			table.remove(items, index)
			break
		end
	end
	item.removed = true
	item.destroyView()
end

local function createItem(itemType, x, y)
	local def = TYPES[itemType]
	local item = {
		kind = "treat",
		type = itemType,
		gauge = def.GAUGE,
		amount = def.AMOUNT,
		x = x,
		y = y,
		width = def.WIDTH,
		height = def.HEIGHT,
		claimedBy = nil,
		removed = false,
	}
	def.new(item, function(dropX, dropY)
		local finalX, finalY = Placement.compute(item.width, item.height, dropX, dropY, item)
		if finalX then
			-- item.x/y so a save taken right now reflects the committed
			-- position, not the pre-drag one.
			item.x, item.y = finalX, finalY
			save()
		end
		return finalX, finalY
	end)
	return item
end

-- Returns true/false, matching what toolbar.lua needs at drop time.
function Treats.tryPlace(itemType, x, y)
	local def = TYPES[itemType]
	if not def then
		return false
	end
	local finalX, finalY = Placement.compute(def.WIDTH, def.HEIGHT, x, y)
	if not finalX then
		return false
	end
	table.insert(items, createItem(itemType, finalX, finalY))
	save()
	return true
end

-- Claims a treat within ALERT_RADIUS of (x, y) for `chicken`, or returns
-- nil. Prefers one helping the chicken's lower gauge, then the nearest
-- (CONTEXT.md's Alert priority). Skips claimed and mid-drag treats.
function Treats.claimNear(chicken, x, y, satiety, cleanliness)
	local best, bestPreferred, bestDistance = nil, false, nil
	for _, item in ipairs(items) do
		if not item.dragging and not item.claimedBy then
			local dx, dy = x - item.x, y - item.y
			local distance = dx * dx + dy * dy
			if distance <= ALERT_RADIUS * ALERT_RADIUS then
				local preferred = (item.gauge == "satiety" and satiety <= cleanliness)
					or (item.gauge == "cleanliness" and cleanliness <= satiety)
				if not best or (preferred and not bestPreferred)
					or (preferred == bestPreferred and distance < bestDistance) then
					best, bestPreferred, bestDistance = item, preferred, distance
				end
			end
		end
	end
	if best then
		best.claimedBy = chicken
	end
	return best
end

-- Frees a treat's claim without consuming it.
function Treats.releaseClaim(item)
	if item and not item.removed then
		item.claimedBy = nil
	end
end

-- Removes a treat; the payoff is applied by the caller.
function Treats.consume(item)
	removeItem(item)
	save()
end

function Treats.getSaveData()
	local saved = {}
	for _, item in ipairs(items) do
		table.insert(saved, { type = item.type, x = item.x, y = item.y })
	end
	return saved
end

-- saved: the "treats" section of src/systems/save.lua's file. Saves from
-- before Treats existed kept mealworms under feed.treats, with no type.
function Treats.load(saved, legacyFeedTreats)
	items = {}
	for _, savedTreat in ipairs(saved or legacyFeedTreats or {}) do
		local itemType = TYPES[savedTreat.type] and savedTreat.type or "mealworm"
		table.insert(items, createItem(itemType, savedTreat.x, savedTreat.y))
	end
end

return Treats
