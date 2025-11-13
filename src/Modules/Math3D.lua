local Math3D = {}
function Math3D.new() 
	local this = {}

	this.rotate = function(object, x, y, z, is_local)
		local is_local = is_local or false
		local rotation = go.get_rotation(object)
		if is_local then
			if x ~= 0 then
				local quat_x = vmath.quat_rotation_x(math.rad(x))
				rotation = rotation * quat_x
			end
			if y ~= 0 then
				local quat_y = vmath.quat_rotation_y(math.rad(y))
				rotation = rotation * quat_y
			end
			if z ~= 0 then
				local quat_z = vmath.quat_rotation_z(math.rad(z))
				rotation = rotation * quat_z
			end
			go.set_rotation(rotation, object)
		else
			if x ~= 0 then
				local quat_x = vmath.quat_rotation_x(math.rad(x))
				rotation = quat_x * rotation
			end
			if y ~= 0 then
				local quat_y = vmath.quat_rotation_y(math.rad(y))
				rotation = quat_y * rotation
			end
			if z ~= 0 then
				local quat_z = vmath.quat_rotation_z(math.rad(z))
				rotation = quat_z * rotation
			end
			go.set_rotation(rotation, object)
		end
	end
	

	this.move = function(object, x, y, z, is_local)
		local is_local = is_local or false
		local position = go.get_position(object)
		local offset = vmath.vector3(x, y, z)
		if is_local then
			local rotation = go.get_rotation(object)
			offset = vmath.rotate(rotation, offset)
			position = position + offset
		else
			position = position + offset
		end
		go.set_position(position, object)
	end
	return this
end

return Math3D.new()