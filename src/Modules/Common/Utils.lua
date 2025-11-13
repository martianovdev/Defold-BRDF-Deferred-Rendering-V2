local Utils = {}
function Utils:new()
	local this = {
		init = function()
		
		end,
		
		table_copy = function(this, original)
			local copy = {}
			for key, value in pairs(original) do
				copy[key] = value
			end
			return copy
		end,

		mutable_copy = function(this, source, target)
			for key, value in pairs(source) do
				target[key] = value
			end
		end,

		url_to_hash = function(this, url)
			return hash(table.concat({
				tostring(url.socket),
				hash_to_hex(url.path),
				hash_to_hex(url.fragment or hash(""))
			}))
		end,


		proxy_to_hash = function(this, url)
			return hash(tostring(url.socket))
		end,

		get_current_socket_hash = function()
			return msg.url().socket
		end
		
	}
	this:init()
	return this
end

return Utils:new()