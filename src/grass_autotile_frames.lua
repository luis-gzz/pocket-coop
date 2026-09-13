-- Generated from assets/GrassTileset/Autotile_BitmaskRef1.png.
--
-- Maps a "TL|TR|BL|BR" corner-state key to the list of matching frame
-- indices (1-based, row-major) in GrassHills.png's 10x6 tile grid. Each
-- corner state is one of:
--   FULL    - both adjacent cardinal neighbors AND the diagonal neighbor
--             match this tile's terrain (no border drawn on that corner)
--   CONCAVE - both adjacent cardinal neighbors match, but the diagonal
--             neighbor doesn't (a small notch is cut into that corner)
--   OPEN    - at least one adjacent cardinal neighbor doesn't match (a
--             border is drawn along that side, per this tileset's style,
--             only for the south/east/west edges - north never draws one)
-- Where a key has more than one frame, they're visually-equivalent variants
-- for random variety.
return {
	["CONCAVE|CONCAVE|CONCAVE|CONCAVE"] = { 28 },
	["CONCAVE|CONCAVE|CONCAVE|FULL"] = { 41 },
	["CONCAVE|CONCAVE|FULL|CONCAVE"] = { 42 },
	["CONCAVE|CONCAVE|FULL|FULL"] = { 24 },
	["CONCAVE|CONCAVE|OPEN|OPEN"] = { 58 },
	["CONCAVE|FULL|CONCAVE|CONCAVE"] = { 51 },
	["CONCAVE|FULL|CONCAVE|FULL"] = { 34 },
	["CONCAVE|FULL|FULL|CONCAVE"] = { 57 },
	["CONCAVE|FULL|FULL|FULL"] = { 32 },
	["CONCAVE|FULL|OPEN|OPEN"] = { 55 },
	["CONCAVE|OPEN|CONCAVE|OPEN"] = { 15 },
	["CONCAVE|OPEN|FULL|OPEN"] = { 44 },
	["CONCAVE|OPEN|OPEN|OPEN"] = { 12 },
	["FULL|CONCAVE|CONCAVE|CONCAVE"] = { 52 },
	["FULL|CONCAVE|CONCAVE|FULL"] = { 47 },
	["FULL|CONCAVE|FULL|CONCAVE"] = { 33 },
	["FULL|CONCAVE|FULL|FULL"] = { 31 },
	["FULL|CONCAVE|OPEN|OPEN"] = { 56 },
	["FULL|FULL|CONCAVE|CONCAVE"] = { 23 },
	["FULL|FULL|CONCAVE|FULL"] = { 22 },
	["FULL|FULL|FULL|CONCAVE"] = { 21 },
	["FULL|FULL|FULL|FULL"] = { 27, 50, 59, 60 },
	["FULL|FULL|OPEN|OPEN"] = { 36, 40 },
	["FULL|OPEN|CONCAVE|OPEN"] = { 54 },
	["FULL|OPEN|FULL|OPEN"] = { 10, 26 },
	["FULL|OPEN|OPEN|OPEN"] = { 19 },
	["OPEN|CONCAVE|OPEN|CONCAVE"] = { 49 },
	["OPEN|CONCAVE|OPEN|FULL"] = { 43 },
	["OPEN|CONCAVE|OPEN|OPEN"] = { 11 },
	["OPEN|FULL|OPEN|CONCAVE"] = { 53 },
	["OPEN|FULL|OPEN|FULL"] = { 20, 25 },
	["OPEN|FULL|OPEN|OPEN"] = { 18 },
	["OPEN|OPEN|CONCAVE|CONCAVE"] = { 4 },
	["OPEN|OPEN|CONCAVE|FULL"] = { 45 },
	["OPEN|OPEN|CONCAVE|OPEN"] = { 2 },
	["OPEN|OPEN|FULL|CONCAVE"] = { 46 },
	["OPEN|OPEN|FULL|FULL"] = { 30, 35 },
	["OPEN|OPEN|FULL|OPEN"] = { 9 },
	["OPEN|OPEN|OPEN|CONCAVE"] = { 1 },
	["OPEN|OPEN|OPEN|FULL"] = { 8 },
	["OPEN|OPEN|OPEN|OPEN"] = { 3, 5, 6, 7, 13, 14, 16, 17, 29, 37, 38, 39, 48 },
}
