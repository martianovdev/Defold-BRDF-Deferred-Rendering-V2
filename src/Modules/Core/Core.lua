local World = require("src.Modules.Core.Modules.World")
local utils = require("src.Modules.Common.Utils")
local Array = require("src.Modules.Common.Array")
local ProxyLoader = require("src.Modules.Common.ProxyLoader")

local Core = {}
function Core:new()
	local this = {
		world_by_socket_hash = {},
		world_array = Array:new(),
		
		init = function(this)
			
		end,

		main = function(this)
			local socket_hash = utils:get_current_socket_hash()
			local new_world_instance = World:new()
			this.world_by_socket_hash[socket_hash] = new_world_instance
		end,
		
		world = function(this, init_callback, update_callback)
			local init_data = ProxyLoader:get_init_data()
			local socket_hash = utils:get_current_socket_hash()
			local new_world_instance = World:new(init_callback, update_callback)
			new_world_instance:init_as_world()
			this.world_by_socket_hash[socket_hash] = new_world_instance
			this.world_array:push(new_world_instance)
		end,
			
		inheritance = function(this)
			
		end,

		unregister = function(this)
			
		end,

		load_proxy = function(this, props)
			ProxyLoader:load_proxy{
				proxy_url = props.proxy_url,
				collection_name = props.collection_name,
				init_data = {
					core_data = {
						parent_socket_hash = utils:get_current_socket_hash()
					},
					user_data = props.init_data
				}
			}
		end,

		get_world = function(this)
			local socket_hash = utils:get_current_socket_hash()
			return this.world_by_socket_hash[socket_hash]
		end,

		get_worlds = function(this)
			return this.world_array.elements
		end,

		subscribe_on_physics_events = function(this, obj_url, event_callback)
			local socket_hash = utils:get_current_socket_hash()
			local proxy_instance = this.world_by_socket_hash[socket_hash]
			proxy_instance:physics_subscribe(obj_url, event_callback)
		end,


		update = function(this)
			local socket_hash = utils:get_current_socket_hash()
			this.world_by_socket_hash[socket_hash]:update()
		end
	}
	this:init()
	return this
end

return Core:new()