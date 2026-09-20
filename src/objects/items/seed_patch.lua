local Constants = require("src.util.constants")
local YSort = require("src.systems.y_sort")
local Tooltip = require("src.ui.tooltip")

-- The view side of a seed patch (CONTEXT.md's Food source). Feed owns the
-- item record (kind/type/x/y/capacity/remaining/offsets) and placement
-- rules; this owns the display object and attaches the updateVisual/
-- destroyView closures Feed calls directly on that record.
local SeedPatch = {}

local ICON_PATH = "assets/objects/seeds_icon.png"
local SPRITE_PATH = "assets/objects/seed.png"
local ICON_NATIVE_SIZE = 20 -- also the seed patch's collision/containment box
local SPRITE_NATIVE_SIZE = 2
local SCATTER_RADIUS_NATIVE = 10
local COUNT = 10

SeedPatch.WIDTH = ICON_NATIVE_SIZE * Constants.PIXEL_SCALE
SeedPatch.HEIGHT = SeedPatch.WIDTH
SeedPatch.CAPACITY = 100
SeedPatch.DESCRIPTOR = { icon = ICON_PATH, width = SeedPatch.WIDTH, height = SeedPatch.HEIGHT, type = "seed_patch" }

-- Scatters the ten seed sprites near the patch's center; generated once and
-- saved so a reload keeps the same arrangement.
function SeedPatch.scatterOffsets()
	local radius = SCATTER_RADIUS_NATIVE * Constants.PIXEL_SCALE
	local offsets = {}
	for _ = 1, COUNT do
		local angle = math.random() * math.pi * 2
		local distance = math.random() * radius
		table.insert(offsets, { dx = math.cos(angle) * distance, dy = math.sin(angle) * distance })
	end
	return offsets
end

-- item: { kind="source", type="seed", x, y, width, height, capacity,
-- remaining, offsets } owned by Feed. Ten seed sprites scattered around its
-- center, hiding one at a time as it depletes. Not registered with YSort -
-- always renders behind, like every other food source.
function SeedPatch.new(item)
	local group = display.newGroup()
	YSort.getGroup():insert(group)
	group.x, group.y = item.x, item.y

	local seedSize = SPRITE_NATIVE_SIZE * Constants.PIXEL_SCALE
	local seeds = {}
	for _, offset in ipairs(item.offsets) do
		local seed = display.newImageRect(group, SPRITE_PATH, seedSize, seedSize)
		seed.x = offset.dx
		seed.y = offset.dy
		table.insert(seeds, seed)
	end

	function item.updateVisual()
		local fraction = item.remaining / item.capacity
		for index, seed in ipairs(seeds) do
			seed.isVisible = fraction > (index - 1) / COUNT
		end
	end
	item.updateVisual()

	function item.destroyView()
		group:removeSelf()
	end

	-- A hit target covering the whole patch, not just the tiny seed sprites.
	local hitArea = display.newRect(group, 0, 0, item.width, item.height)
	hitArea:setFillColor(0, 0, 0, 0.01)
	hitArea:addEventListener("tap", function()
		Tooltip.show({
			x = item.x,
			y = item.y,
			rows = {
				{ label = "Seed patch", getValue = function() return item.remaining / item.capacity * 100 end },
			},
		})
		return true
	end)

	return group
end

return SeedPatch
