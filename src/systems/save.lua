local json = require("json")

-- Plain JSON file persistence (ADR-0003): no offline catchup math, values
-- just resume exactly as saved next launch.
local Save = {}

local FILE_NAME = "chicken_save.json"

local function getPath()
	return system.pathForFile(FILE_NAME, system.DocumentsDirectory)
end

function Save.load()
	local path = getPath()
	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local contents = file:read("*a")
	file:close()

	local ok, data = pcall(json.decode, contents)
	if not ok or type(data) ~= "table" then
		return nil
	end
	return data
end

function Save.write(data)
	local path = getPath()
	local file = io.open(path, "w")
	if not file then
		return
	end
	file:write(json.encode(data))
	file:close()
end

return Save
