local Tuning = require("src.systems.tuning")
local Bed = require("src.objects.items.bed")
local SeedPatch = require("src.objects.items.seed_patch")
local Lettuce = require("src.objects.items.lettuce")
local Mealworm = require("src.objects.items.mealworm")
local Ash = require("src.objects.items.ash")
local WaterBowl = require("src.objects.items.water_bowl")
local Bucket = require("src.objects.items.bucket")
local Watermelon = require("src.objects.items.watermelon")

-- The single place that knows the toolbar's item list (CONTEXT.md's
-- Toolbar) - each entry's icon/width/height/type comes straight from its
-- own item file, so toolbar.lua never needs to require Garden/Feed just to
-- know what's placeable. Adding a new placeable item later is one more line
-- here plus its own item file.
local Catalog = {
	Bed.DESCRIPTOR,
	WaterBowl.DESCRIPTOR,
	Bucket.DESCRIPTOR,
	SeedPatch.DESCRIPTOR,
	Lettuce.DESCRIPTOR,
	Mealworm.DESCRIPTOR,
	Watermelon.DESCRIPTOR,
	Ash.DESCRIPTOR,
}
-- Tools (the bucket) have no price and never run out (CONTEXT.md's Tool).
for _, item in ipairs(Catalog) do
	item.price = Tuning.PRICES[item.type]
end

return Catalog
