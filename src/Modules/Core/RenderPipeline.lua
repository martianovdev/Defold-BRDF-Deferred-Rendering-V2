local World = require("src.Modules.Core.Modules.World")
local utils = require("src.Modules.Common.Utils")
local Array = require("src.Modules.Common.Array")
local ProxyLoader = require("src.Modules.Common.ProxyLoader")

local RenderPipeline = {}
function RenderPipeline:new()
	local this = {
		world_by_socket_hash = {},
		world_array = Array:new(),

		init = function(this)

		end
	}
	this:init()
	return this
end

return RenderPipeline:new()