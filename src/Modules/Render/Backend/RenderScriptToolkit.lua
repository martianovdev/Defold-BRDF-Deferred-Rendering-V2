local RenderTarget = require("src.Modules.Render.Backend.Modules.RenderTarget")

local RenderScriptToolkit = {}
function RenderScriptToolkit:new(render_properties, predicate)
	local this = {
		current_render_target = nil, -- currently active render target
		current_material = nil,      -- currently active material
		current_camera = nil,

		main_render_props = render_properties,
		main_predicate = predicate,
		
		-- Create a new render target (framebuffer) with given size and attachments
		create_render_target = function(this, width, height, attachments)
			return RenderTarget:new(width, height, attachments)
		end,
		
		-- Temporarily bind a render target, run a callback, then restore the previous one
		bind_render_target = function(this, target_rt, callback)
			local temp_rt = this.current_render_target
			this.current_render_target = target_rt

			target_rt:enable()
			target_rt:clear()
			
			callback() -- do the rendering into this RT
			
			-- restore previous render target (or default one)
			if temp_rt ~= nil then
				temp_rt:enable()
			else
				render.set_render_target(render.RENDER_TARGET_DEFAULT)
			end

			this.current_render_target = temp_rt
		end,

		-- Temporarily bind a material, run a callback, then restore the previous one
		bind_material = function(this, material_name, callback)
			local temp_mt = this.current_material
			this.current_material = material_name

			render.enable_material(material_name)
			callback()

			-- restore previous material (or disable if none)
			if temp_mt ~= nil then
				render.enable_material(temp_mt)
			else
				render.disable_material()
			end

			this.current_material = temp_mt
		end,

		-- Render scene using a given camera into the current render target
		render_camera = function(this, camera, callback)
			local target = this.current_render_target
	
			-- make sure camera matches target resolution
			if(camera.render_width ~= target.width or camera.render_height ~= target.height) then
				camera:resize(target.width, target.height)
			end

			-- setup viewport and camera matrices
			render.set_viewport(0, 0, target.width, target.height)
			render.set_view(camera.view)
			render.set_projection(camera.projection)

			-- enable depth test and face culling for proper 3D rendering
			render.enable_state(graphics.STATE_CULL_FACE)
			render.enable_state(graphics.STATE_DEPTH_TEST)

			this.current_camera = camera
			callback() -- actual scene rendering

			-- cleanup: disable states
			render.disable_state(graphics.STATE_DEPTH_TEST)
			render.disable_state(graphics.STATE_CULL_FACE)
		end,

		-- Render multiple cubemaps into a single atlas (each cubemap = 6 faces)
		render_multi_cubemap = function(this, source_position, cubemap_index, cubemap_size, callback)
			local target = this.current_render_target
			local RTW, RTH = target.width, target.height

			-- side size of one cube face
			local face = cubemap_size
			-- number of cube faces that can fit horizontally and vertically in the atlas
			local cols = math.floor(RTW / face)
			local rows = math.floor(RTH / face)

			assert(cols * rows >= 6, "Atlas too small for even one cubemap")

			-- 6 face directions (+X, -X, +Y, -Y, +Z, -Z)
			local views = {
				vmath.matrix4_look_at(source_position, source_position + vmath.vector3( 1,  0,  0), vmath.vector3(0, 1,  0)), -- +X
				vmath.matrix4_look_at(source_position, source_position + vmath.vector3(-1,  0,  0), vmath.vector3(0, 1,  0)), -- -X
				vmath.matrix4_look_at(source_position, source_position + vmath.vector3( 0,  1,  0), vmath.vector3(0, 0, -1)), -- +Y
				vmath.matrix4_look_at(source_position, source_position + vmath.vector3( 0, -1,  0), vmath.vector3(0, 0,  1)), -- -Y
				vmath.matrix4_look_at(source_position, source_position + vmath.vector3( 0,  0,  1), vmath.vector3(0, 1,  0)), -- +Z
				vmath.matrix4_look_at(source_position, source_position + vmath.vector3( 0,  0, -1), vmath.vector3(0, 1,  0)), -- -Z
			}

			-- 90° FOV projection for cube face
			local projection = vmath.matrix4_perspective(math.rad(90), 1.0, 0.01, 100.0)

			for faceIndex = 0, 5 do
				-- index of current cube face in the atlas
				local globalIndex = cubemap_index * 6 + faceIndex
				local gx = globalIndex % cols
				local gy = math.floor(globalIndex / cols)

				-- calculate viewport position inside atlas
				local vx = gx * face
				local vy = RTH - (gy + 1) * face -- origin is bottom-left

				-- setup camera for this face
				render.set_view(views[faceIndex + 1])
				render.set_projection(projection)
				render.set_viewport(vx, vy, face, face)

				render.enable_state(render.STATE_CULL_FACE)
				render.enable_state(render.STATE_DEPTH_TEST)

				local draw_options = {
					frustum = projection*views[faceIndex + 1],
					sort_order = render.SORT_FRONT_TO_BACK
				}
				callback(draw_options) -- render the scene for this cube face

				-- cleanup states
				render.disable_state(render.STATE_DEPTH_TEST)
				render.disable_state(render.STATE_CULL_FACE)
			end

			
		end,

		-- Draw contents of one render target into another (postprocessing, compositing)
		draw_render_target = function(this, source_render_target, x, y, w, h, attachments, custom_constants)
			local target = this.current_render_target

			-- if attachments is a single number → convert to table
			if type(attachments) == "number" then
				attachments = { attachments }
			elseif attachments == nil then
				-- default: use color attachment
				attachments = { graphics.BUFFER_TYPE_COLOR0_BIT }
			end

			-- bind all attachments as textures
			for i, attachment in ipairs(attachments) do
				render.enable_texture(i - 1, attachment[1].render_target, attachment[2])
			end

			-- default viewport is full RT size if not specified
			local vx = x or 0
			local vy = y or 0
			local vw = 0 
			local vh = 0

			local constants = nil
			
			if(target) then
				vw = w or target.width
				vh = h or target.height
				constants = target.constants
			else
				vw = w or this.main_render_props.width
				vh = h or this.main_render_props.height
				constants = this.main_render_props.constants
			end


			render.set_viewport(vx, vy, vw, vh)
			render.set_view(this.main_render_props.view)
			render.set_projection(this.main_render_props.projection)

			if custom_constants then
				for k, v in pairs(custom_constants) do
					constants[k] = v
				end
			end
			constants.size = vmath.vector4(vw, vh, 0, 0)
			
			local draw_options = {
				constants = constants
			}

			-- draw with blending enabled (useful for transparency / overlays)
			render.enable_state(graphics.STATE_BLEND)
			render.draw(this.main_predicate, draw_options)
			render.disable_state(graphics.STATE_BLEND)

			-- unbind all textures
			for i = 1, #attachments do
				render.disable_texture(i - 1)
			end
		end,

		draw_predicate = function(this, pred, custom_constants)
			local target = this.current_render_target
			-- setup constants (screen size, custom params)
			local constants = target.constants

			local vw = target.width
			local vh = target.height
			
			if custom_constants then
				for k, v in pairs(custom_constants) do
					constants[k] = v
				end
			end
			constants.size = vmath.vector4(vw, vh, 0, 0)
			local draw_options = {
				constants = constants,
				frustum = this.current_camera.frustum,
				sort_order = render.SORT_NONE
			}
			
			render.draw(pred, draw_options)
			
		end,

-- 		bind_screen = function(this, attachment)
-- 			render.clear(this.main_render_props.clear_buffers)
-- 			render.enable_texture(0,  attachment[1],  attachment[2])
-- 
-- 			render.set_viewport(0, 0, self.render_properties.width, self.render_properties.height)
-- 			render.set_view(self.render_properties.view)
-- 			render.set_projection(self.render_properties.projection)
-- 
-- 			render.enable_state(render.STATE_BLEND)
-- 			render.draw(self.predicates.render_root, self.render_properties.frustum)
-- 
-- 			render.disable_state(render.STATE_BLEND)
-- 			render.disable_texture(0)
-- 		end

		
	}

	return this
end

return RenderScriptToolkit
