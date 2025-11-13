local Camera = {}
function Camera:new()
	local this = {
		view = vmath.matrix4(),
		fov = 90,
		near = 0.01,
		far = 100.0,
		aspect_ratio = 1.0,
		transform = vmath.matrix4(),
		projection = vmath.matrix4_perspective(math.rad(75), 1.0, 0.1, 100),
		frustum = vmath.matrix4(),
		render_width = 0,
		render_height = 0,
		
		init = function(this)

		end,

		resize = function(this, width, height)
			if (width > 0 and height > 0) then
				this.render_width = width
				this.render_height = height
				this.aspect_ratio = width / height
				this:update_projection()
			end
		end,
		
		update_projection = function(this)
			this.projection = vmath.matrix4_perspective(math.rad(this.fov), this.aspect_ratio, this.near, this.far)
			this.frustum = this.projection * this.view
		end,
	}
	this:init() 
	return this
end

return Camera