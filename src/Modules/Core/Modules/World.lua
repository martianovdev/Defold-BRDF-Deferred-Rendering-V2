local IDManager = require("src.Modules.Common.IDManager")
local PhysicsMaster = require("src.Modules.Common.PhysicsMaster")

local Camera = require("src.Modules.Core.Modules.Camera")
local LightSource = require("src.Modules.Core.Modules.LightSource")

local World = {}
function World:new(init_callback, update_callback)
	local this = {
		physics_master = PhysicsMaster:new(),
		light_id_manager = IDManager:new(),

		camera_by_tag = {},
		camera_by_id = {},
		camera_id_manager = IDManager:new(),

		initialized = false,
		props = {},
		init_callback = init_callback,
		update_callback = update_callback,

		render_pipeline = {
			buffers = {}
		},

		-- Light sources
		light_source_by_id = {},
		light_source_flat_arrays = {
			transform_array = {},
			color_array = {},
			properties_array = {},
			vol_params_array = {}
		},
		
		ambient_color = vmath.vector4(0.1, 0.1, 0.1, 1),
		
		init = function(this)
			physics.set_listener(function(_, event, data)
				this.physics_master:update(event, data)
			end)
		end,

		init_as_world = function(this)

		end,

		initialize_render = function(this, toolkit)
			this.props = this.init_callback(toolkit)
			this.initialized = true
		end,

		render = function(this, toolkit, render_width, render_height)
			this.update_callback(toolkit, this, this.props, render_width, render_height)
		end,

		physics_subscribe = function(this, obj_url, event_callback)
			this.physics_master:subscribe(obj_url, event_callback)
		end,

		update = function(this)
			
		end,

		-- Lights
		create_light_source = function(this)
			local new_id = this.light_id_manager:get()
			local new_light_source = LightSource:new()
			this.light_source_by_id[new_id] = new_light_source
			this:_update_flat_arrays()
			return new_id
		end,

		remove_light_source = function(this, id)
			this.light_id_manager:free(id)
			--remove logic
		end,

		light_set_transform = function(this, id, transform)
			local light_source = this.light_source_by_id[id]
			light_source.transform = transform
			if(light_source.flat_index ~= 0) then
				this.light_source_flat_arrays.transform_array[light_source.flat_index] = transform
			end
		end,

		light_set_color = function(this, id, color)
			local light_source = this.light_source_by_id[id]
			light_source.color = color
			if(light_source.flat_index ~= 0) then
				this.light_source_flat_arrays.color_array[light_source.flat_index] = color
			end
		end,

		light_set_type = function(this, id, type)
			local light_source = this.light_source_by_id[id]
			light_source.properties.x = type
		end,

		light_set_radius = function(this, id, radius)
			local light_source = this.light_source_by_id[id]
			light_source.properties.y = radius
		end,

		light_set_volume_radius = function(this, id, radius)
			local light_source = this.light_source_by_id[id]
			light_source.properties.z = radius
		end,

		light_set_shadows = function(this, id, enable)
			local light_source = this.light_source_by_id[id]
			if(enable) then light_source.properties.w = 1.0 else light_source.properties.w = 0.0 end
		end,

		_update_flat_arrays = function(this)
			this.light_source_flat_arrays.transform_array = {}
			this.light_source_flat_arrays.color_array = {}
			this.light_source_flat_arrays.properties_array = {}
			for index, light_source in ipairs(this.light_source_by_id) do
				table.insert(this.light_source_flat_arrays.transform_array, light_source.transform)
				table.insert(this.light_source_flat_arrays.color_array, light_source.color)
				table.insert(this.light_source_flat_arrays.properties_array, light_source.properties)
				light_source.flat_index = index
			end
		end,

		-- Cameras
		create_camera = function(this, tag_hash)
			local new_id = this.camera_id_manager:get()
			local new_camera = Camera:new()
			
			this.camera_by_id[new_id] = new_camera
			this.camera_by_tag[tag_hash] = new_camera
			return new_id
		end,

		remove_camera = function(this, id)
			this.camera_id_manager:free(id)
		end,

		get_camera = function(this, tag)
			return this.camera_by_tag[tag]
		end,
		
		camera_set_transform = function(this, id, transform)
			local camera = this.camera_by_id[id]
			camera.transform = transform
		end,

		camera_set_view = function(this, id, view)
			local camera = this.camera_by_id[id]
			camera.view = view
			camera:update_projection() 
		end
	}
	this:init()
	return this
end

return World