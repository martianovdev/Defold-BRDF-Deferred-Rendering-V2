local utils = require("src.Modules.Common.Utils")

local CollectionStore = {}
function CollectionStore:new()
	local this = {
		init = function(this)
			this.env_data_by_url = {}
		end,

		set = function(this, env_data)
			local url_hash = utils:proxy_to_hash(msg.url())
			this.env_data_by_url[url_hash] = env_data
			return env_data
		end,

		get = function(this)
			local url_hash = utils:proxy_to_hash(msg.url())
			return this.env_data_by_url[url_hash]
		end
	}
	this:init()
	return this
end

return CollectionStore:new()