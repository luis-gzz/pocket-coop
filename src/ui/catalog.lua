local Bed = require("src.objects.items.bed")
local SeedPatch = require("src.objects.items.seed_patch")
local Lettuce = require("src.objects.items.lettuce")
local Mealworm = require("src.objects.items.mealworm")

-- The single place that knows the toolbar's item list (CONTEXT.md's
-- Toolbar) - each entry's icon/width/height/type comes straight from its
-- own item file, so toolbar.lua never needs to require Garden/Feed just to
-- know what's placeable. Adding a new placeable item later is one more line
-- here plus its own item file.
return {
	Bed.DESCRIPTOR,
	SeedPatch.DESCRIPTOR,
	Lettuce.DESCRIPTOR,
	Mealworm.DESCRIPTOR,
}
