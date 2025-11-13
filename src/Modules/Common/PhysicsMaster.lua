local utils = require("src.Modules.Common.Utils")

local PhysicsMaster = {}
function PhysicsMaster:new()
	local this = {
		callback_by_path = {},
		
		init = function(this)
			
		end,

		subscribe = function(this, obj_url, event_callback)
			this.callback_by_path[obj_url.path] = event_callback
		end,

		update = function(this, event, data)
			if event == hash("contact_point_event") then
				-- Handle detailed contact point data

				if(data.distance > 0) then
					local a_callback = this.callback_by_path[data.a.id]
					local b_callback = this.callback_by_path[data.b.id]
					if(a_callback ~= nil) then
						a_callback(data, data.b)
					else
						if(b_callback ~= nil) then
							b_callback(data, data.a)
						end
					end
				end
			end
		end

	}
	this:init()
	return this
end

return PhysicsMaster