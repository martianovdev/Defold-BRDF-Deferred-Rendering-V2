local LightSource = {}
function LightSource:new()
	local this = {
		flat_index = 0,
		transform = vmath.vector4(),
		color = vmath.vector4(0, 0, 0, 1.0), -- r, g, b, power
		properties =  vmath.vector4(0, 0, 0, 0), -- type_index, radius, volume_radius, shadows 

		init = function(this)
		
		end,
	}
	this:init()
	return this
end
return LightSource