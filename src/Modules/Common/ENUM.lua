function ENUM(tbl)
	local enum = {}
	for i, v in ipairs(tbl) do
		enum[v] = i-1
	end
	return enum
end

return ENUM