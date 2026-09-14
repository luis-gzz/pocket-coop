local Constants = {}

-- Uniform pixel-art scale factor: how many screen points each native sprite
-- pixel occupies. Applied to every piece of art so pixel density stays
-- consistent regardless of an asset's native resolution. Raise this to zoom
-- the whole game in.
Constants.PIXEL_SCALE = 3

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
