local utils = require("src.Modules.Common.Utils")

local Render = {}
function Render:new()
	local this = {
		callback_by_path = {},

		init = function(this)

		end,
	}
	this:init()
	return this
end

return Render