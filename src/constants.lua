local Constants = {}

-- Uniform pixel-art scale factor: how many screen points each native sprite
-- pixel occupies. Applied to every piece of art so pixel density stays
-- consistent regardless of an asset's native resolution. Raise this to zoom
-- the whole game in.
Constants.PIXEL_SCALE = 2

-- Matches the grass tileset's native grid (assets/GrassTileset), which is
-- also the same grid the chicken and fence art are drawn on.
Constants.TILE_NATIVE_SIZE = 16
Constants.TILE_SIZE = Constants.TILE_NATIVE_SIZE * Constants.PIXEL_SCALE

return Constants
