local YSort = require("src.systems.y_sort")
local Wiggle = require("src.util.wiggle")
local Tooltip = require("src.ui.tooltip")

-- The view + drag side shared by every treat (CONTEXT.md's Treat): a
-- sprite that a long press picks up and drags, and a short tap opens its
-- tooltip. Treats owns the item record and placement rules.
local TreatView = {}

-- ms; matches chicken.lua's own long-press threshold.
local LONG_PRESS_TIME = 350
local WIGGLE_ANGLE = 8
local WIGGLE_STEP_TIME = 90

-- item: { x, y, width, height, claimedBy, removed, dragging } owned by
-- Treats. Picking it up frees any claim, and it can't be claimed again
-- until it's put down.
--
-- opts: { image, floor (render in the floor layer instead of the main
-- sort), depthBias (main sort only), tooltip (content for Tooltip.show,
-- minus x/y) }.
--
-- resolveDrop(x, y) is Treats' own placement check (excluding this item) -
-- it returns the final (possibly nudged) x, y on a valid drop, or nil to
-- snap back.
function TreatView.new(item, opts, resolveDrop)
	local sprite = display.newImageRect(opts.image, item.width, item.height)
	sprite.x = item.x
	sprite.y = item.y
	if opts.floor then
		YSort.getFloorGroup():insert(sprite)
	else
		YSort.getGroup():insert(sprite)
		local halfHeight = item.height / 2
		local bias = opts.depthBias or 0
		YSort.add(sprite, function(view)
			return view.y + halfHeight - bias
		end)
	end

	local pendingTouch = false
	local isDragging = false
	local longPressHandle = nil
	local originalX, originalY
	local dragOffsetX, dragOffsetY
	local wiggleHandle = nil

	local function beginDrag(startX, startY)
		isDragging = true
		item.dragging = true
		if item.claimedBy then
			item.claimedBy:abandonTarget()
		end
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
	end

	local function showTooltip()
		local content = {}
		for key, value in pairs(opts.tooltip) do
			content[key] = value
		end
		content.x, content.y = item.x, item.y
		Tooltip.show(content)
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

				-- Released before the long press fired: a tap, so open the tooltip.
				if longPressHandle then
					timer.cancel(longPressHandle)
					longPressHandle = nil
					if pendingTouch and event.phase == "ended" then
						showTooltip()
					end
				end
				pendingTouch = false

				if isDragging then
					isDragging = false
					Wiggle.stop(wiggleHandle)
					wiggleHandle = nil
					-- Releasing in place synthesizes a tap; don't let it close a tooltip.
					Tooltip.ignoreNextTap()
					local finalX, finalY
					if event.phase == "ended" then
						finalX, finalY = resolveDrop(sprite.x, sprite.y)
					end
					if finalX then
						moveTo(finalX, finalY)
						item.dragging = false
					else
						transition.to(sprite, {
							x = originalX,
							y = originalY,
							time = 150,
							onComplete = function()
								moveTo(originalX, originalY)
								item.dragging = false
							end,
						})
					end
				end
			end
		end
		return true
	end
	sprite:addEventListener("touch", onTouch)

	-- Solar2D hit-tests "tap" separately from "touch" - this blocks a tap
	-- falling through to the tooltip's dismiss target underneath.
	sprite:addEventListener("tap", function()
		return true
	end)

	function item.destroyView()
		if not opts.floor then
			YSort.remove(sprite)
		end
		sprite:removeSelf()
	end

	return sprite
end

return TreatView
