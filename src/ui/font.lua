local Constants = require("src.util.constants")

-- Positions text by its ink rather than its newText box, whose built-in
-- leading varies per font. See Constants.FONT_CAP_TOP / FONT_BASELINE.
local Font = {}

-- Height of the UI font's capitals (and digits) at the given size.
function Font.capHeight(fontSize)
	return fontSize * (Constants.FONT_BASELINE - Constants.FONT_CAP_TOP)
end

-- Ink height of a (possibly multi-line) text: first line's cap top to last
-- line's baseline.
function Font.inkHeight(text, fontSize)
	return text.height - fontSize * (Constants.FONT_CAP_TOP + Constants.FONT_DESCENT)
end

-- Top-anchors text so its capitals' top edge lands on y.
function Font.placeCapsAt(text, y, fontSize)
	text.anchorY = 0
	text.y = y - fontSize * Constants.FONT_CAP_TOP
end

-- Top-anchors text so its capitals are vertically centered on centerY.
function Font.centerCapsOn(text, centerY, fontSize)
	Font.placeCapsAt(text, centerY - Font.capHeight(fontSize) / 2, fontSize)
end

return Font
