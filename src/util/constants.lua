local Constants = {}

-- Uniform pixel-art scale factor: how many screen points each native sprite
-- pixel occupies. Applied to every piece of art so pixel density stays
-- consistent regardless of an asset's native resolution.
--
-- Device-dependent rather than a flat constant: a fixed contentWidth
-- (config.lua) means a squarer device (an iPad, ~4:3) has proportionally
-- less vertical content space than a tall one (an iPhone X, ~19.5:9), so the
-- same scale reads as too zoomed-in on the squarer device. Calibrated
-- against those two real ratios and linearly interpolated (clamped) between
-- them, since aspect ratio is a continuum, not just two device families.
local function computePixelScale()
	local ratio = display.pixelHeight / display.pixelWidth

	local TABLET_RATIO, TABLET_SCALE = 4 / 3, 2
	local PHONE_RATIO, PHONE_SCALE = 19.5 / 9, 3

	local t = (ratio - TABLET_RATIO) / (PHONE_RATIO - TABLET_RATIO)
	t = math.max(0, math.min(1, t))
	local scale = TABLET_SCALE + (PHONE_SCALE - TABLET_SCALE) * t

	-- Ratio alone breaks for a small, squarish-ratio phone (an iPhone 4 at
	-- 3:2 reads as tablet-like by ratio and gets the smaller scale, even
	-- though its tiny physical screen needs the phone scale just as much as
	-- a tall modern phone does). Below this raw-pixel width, always floor to
	-- the phone scale regardless of ratio - comfortably under every iPad's
	-- short edge (768+) and every modern phone's (1080+), so this only
	-- catches genuinely small/old screens.
	local SMALL_SCREEN_WIDTH = 700
	local shortEdge = math.min(display.pixelWidth, display.pixelHeight)
	if shortEdge <= SMALL_SCREEN_WIDTH then
		scale = math.max(scale, PHONE_SCALE)
	end

	return scale
end

Constants.PIXEL_SCALE = computePixelScale()

-- Matches the grass tileset's native grid (assets/GrassTileset), which is
-- also the same grid the chicken and fence art are drawn on.
Constants.TILE_NATIVE_SIZE = 16
Constants.TILE_SIZE = Constants.TILE_NATIVE_SIZE * Constants.PIXEL_SCALE

-- Shared UI font. Referenced by its resource-relative path; Solar2D accepts
-- that directly on the Simulator/Android. An iOS build will additionally
-- need it declared under build.settings' ios.plist.UIAppFonts.
Constants.FONT = "assets/font/Awkward/Awkward.ttf"

-- Font sizes in "native" units, scaled by PIXEL_SCALE like every other piece
-- of art, so text grows/shrinks along with the rest of the game instead of
-- staying a fixed point size.
Constants.FONT_SIZE_SMALL = 14 * Constants.PIXEL_SCALE
Constants.FONT_SIZE_LARGE = 16 * Constants.PIXEL_SCALE

return Constants
