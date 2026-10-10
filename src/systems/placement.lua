local Constants = require("src.util.constants")
local Layout = require("src.ui.layout")

-- Shared spacing for food sources and treats (CONTEXT.md): a drop too close
-- to any registered item is nudged. Feed and Treats each register their list.
local Placement = {}

-- Placing an item within this distance of another's center just nudges
-- it a little, rather than blocking the placement - purely so two items
-- don't render right on top of each other. A center-to-center distance
-- rather than a footprint overlap, so it doesn't depend on either item's
-- own box size.
local OVERLAP_TRIGGER_DISTANCE = Constants.TILE_SIZE / 2
-- About a tile, so the nudge itself is actually visible.
local OVERLAP_JITTER_RADIUS = Constants.TILE_SIZE

local itemSources = {}

-- getItems returns the owner's current item list (re-read on every check,
-- since load() replaces the list wholesale).
function Placement.register(getItems)
	table.insert(itemSources, getItems)
end

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function isWithinPlayArea(x, y, width, height)
	local bounds = Layout.getPlayArea()
	return x - width / 2 >= bounds.minX
		and x + width / 2 <= bounds.maxX
		and y - height / 2 >= bounds.minY
		and y + height / 2 <= bounds.maxY
end

-- Clamps (x, y) so a width x height footprint stays fully within the play area.
local function clampToPlayArea(x, y, width, height)
	local bounds = Layout.getPlayArea()
	return clamp(x, bounds.minX + width / 2, bounds.maxX - width / 2),
		clamp(y, bounds.minY + height / 2, bounds.maxY - height / 2)
end

local function hasNearbyItem(x, y, exclude)
	local limit = OVERLAP_TRIGGER_DISTANCE * OVERLAP_TRIGGER_DISTANCE
	for _, getItems in ipairs(itemSources) do
		for _, item in ipairs(getItems()) do
			local dx, dy = x - item.x, y - item.y
			if item ~= exclude and dx * dx + dy * dy < limit then
				return true
			end
		end
	end
	return false
end

-- Rejects a drop outside the play area (nil, nil); otherwise always
-- succeeds, nudging a little (clamped back into the play area) if it lands
-- too close to another item's center.
function Placement.compute(width, height, x, y, exclude)
	if not isWithinPlayArea(x, y, width, height) then
		return nil, nil
	end

	if hasNearbyItem(x, y, exclude) then
		local angle = math.random() * math.pi * 2
		local distance = math.random() * OVERLAP_JITTER_RADIUS
		x, y = clampToPlayArea(x + math.cos(angle) * distance, y + math.sin(angle) * distance, width, height)
	end

	return x, y
end

return Placement
