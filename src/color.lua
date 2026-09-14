-- Small color utility, adapted from JumpyLlamaRedux's hex2rgb helper.
local Color = {}

-- Converts a "RRGGBB" or "RGB" hex string (leading "#" optional) to r, g, b
-- floats in the 0-1 range display objects expect.
function Color.hexToRGB(hex)
	hex = hex:gsub("#", "")
	if #hex == 3 then
		local r, g, b = hex:sub(1, 1), hex:sub(2, 2), hex:sub(3, 3)
		return tonumber(r .. r, 16) / 255, tonumber(g .. g, 16) / 255, tonumber(b .. b, 16) / 255
	end
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

return Color
