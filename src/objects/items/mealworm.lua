local Constants = require("src.util.constants")
local YSort = require("src.systems.y_sort")
local Wiggle = require("src.util.wiggle")

-- The view + drag side of a mealworm (CONTEXT.md's Treat) - the only
-- draggable food item. Feed owns the item record and placement/overlap
-- rules; this owns the display object and drag mechanics.
local Mealworm = {}

local IMAGE_PATH = "assets/objects/mealworm.png"
local NATIVE_WIDTH, NATIVE_HEIGHT = 12, 5

Mealworm.WIDTH = NATIVE_WIDTH * Constants.PIXEL_SCALE
Mealworm.HEIGHT = NATIVE_HEIGHT * Constants.PIXEL_SCALE
Mealworm.DESCRIPTOR = { icon = IMAGE_PATH, width = Mealworm.WIDTH, height = Mealworm.HEIGHT, type = "mealworm" }

-- ms; matches chicken.lua's own long-press threshold.
local LONG_PRESS_TIME = 350
local WIGGLE_ANGLE = 8
local WIGGLE_STEP_TIME = 90

-- item: { kind="treat", type="mealworm", x, y, width, height, claimedBy,
-- removed } owned by Feed. Dragging it while claimed keeps the claim and
-- re-targets the chicken mid-walk.
--
-- resolveDrop(x, y) is Feed's own overlap/bounds check (today's
-- computePlacement, excluding this item) - it returns the final (possibly
-- nudged) x, y on a valid drop, or nil to snap back. Placement validity
-- needs Feed's live item list (to avoid stacking on another food item), so
-- it can't be self-contained the way a bed's re-drag check is.
function Mealworm.new(item, resolveDrop)
	local width, height = item.width, item.height
	local sprite = display.newImageRect(IMAGE_PATH, width, height)
	YSort.getGroup():insert(sprite)
	sprite.x = item.x
	sprite.y = item.y
	YSort.add(sprite, function(view)
		return view.y + height / 2
	end)

	local pendingTouch = false
	local isDragging = false
	local longPressHandle = nil
	local originalX, originalY
	local dragOffsetX, dragOffsetY
	local wiggleHandle = nil

	local function beginDrag(startX, startY)
		isDragging = true
		originalX, originalY = item.x, item.y
		dragOffsetX = sprite.x - startX
		dragOffsetY = sprite.y - startY
		wiggleHandle = Wiggle.start(sprite, WIGGLE_ANGLE, WIGGLE_STEP_TIME, function()
			return isDragging
		end)
	end

	local function moveTo(x, y)
		sprite.x, sprite.y = x, y
		item.x, item.y = x, y
		if item.claimedBy and item.claimedBy.retargetApproach then
			item.claimedBy:retargetApproach()
		end
	end

	local function onTouch(event)
		if event.phase == "began" then
			display.getCurrentStage():setFocus(sprite, event.id)
			sprite.isFocus = true
			pendingTouch = true
			local startX, startY = event.x, event.y
			longPressHandle = timer.performWithDelay(LONG_PRESS_TIME, function()
				longPressHandle = nil
				if pendingTouch then
					beginDrag(startX, startY)
					pendingTouch = false
				end
			end)
		elseif sprite.isFocus then
			if event.phase == "moved" then
				if isDragging then
					moveTo(event.x + dragOffsetX, event.y + dragOffsetY)
				end
			elseif event.phase == "ended" or event.phase == "cancelled" then
				display.getCurrentStage():setFocus(sprite, nil)
				sprite.isFocus = false

				if longPressHandle then
					timer.cancel(longPressHandle)
					longPressHandle = nil
				end
				pendingTouch = false

				if isDragging then
					isDragging = false
					Wiggle.stop(wiggleHandle)
					wiggleHandle = nil
					local finalX, finalY
					if event.phase == "ended" then
						finalX, finalY = resolveDrop(sprite.x, sprite.y)
					end
					if finalX then
						moveTo(finalX, finalY)
					else
						transition.to(sprite, {
							x = originalX,
							y = originalY,
							time = 150,
							onComplete = function()
								moveTo(originalX, originalY)
							end,
						})
					end
				end
			end
		end
		return true
	end
	sprite:addEventListener("touch", onTouch)

	function item.destroyView()
		YSort.remove(sprite)
		sprite:removeSelf()
	end

	return sprite
end

return Mealworm
