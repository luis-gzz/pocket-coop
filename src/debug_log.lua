-- Writes a quick diagnostic line to a file. Useful when print() output isn't
-- reachable (Solar2D routes it to the separate CoronaConsole process rather
-- than the simulator's own stdout).
local DebugLog = {}

local FILE_NAME = "debug.log"

function DebugLog.write(...)
	local path = system.pathForFile(FILE_NAME, system.DocumentsDirectory)
	local file = io.open(path, "a")
	if not file then
		return
	end

	local parts = { ... }
	for i, value in ipairs(parts) do
		parts[i] = tostring(value)
	end
	file:write(table.concat(parts, " ") .. "\n")
	file:close()
end

return DebugLog
