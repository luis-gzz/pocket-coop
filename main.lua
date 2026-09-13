display.setStatusBar(display.HiddenStatusBar)

-- Keep the 16px pixel art crisp at the non-integer scale factors the
-- letterbox content scaling can produce across devices.
display.setDefault("minTextureFilter", "nearest")
display.setDefault("magTextureFilter", "nearest")

-- Backdrop behind the island, filling the whole camera.
display.setDefault("background", 0xA2 / 0xFF, 0xDC / 0xFF, 0xC7 / 0xFF)

local Island = require("src.island")
local Chicken = require("src.chicken")

Island.create()
Chicken.new()
