local Array = {}
function Array:new()
	local this = {
		elements = {},  -- Array to store elements
		indices = {},   -- Hash table to store element indices
		size = 0,        -- Current array size

		push = function(this, element)
			this.size = this.size + 1
			this.elements[this.size] = element

			if not this.indices[element] then
				this.indices[element] = {}
			end
			table.insert(this.indices[element], this.size)
		end,

		remove = function(this, element)
			local index_list = this.indices[element]
			if not index_list or #index_list == 0 then
				return false  -- Element not found
			end

			local index = table.remove(index_list)
			if #index_list == 0 then
				this.indices[element] = nil
			end

			if index ~= this.size then
				local last_element = this.elements[this.size]
				this.elements[index] = last_element

				local last_element_indices = this.indices[last_element]
				for i = 1, #last_element_indices do
					if last_element_indices[i] == this.size then
						last_element_indices[i] = index
						break
					end
				end
			end

			this.elements[this.size] = nil
			this.size = this.size - 1
			return true
		end,

		for_each = function(this, callback)
			for i = 1, this.size do
				callback(this.elements[i], i)
			end
		end,

		reverse_for_each = function(this, callback)
			for i = this.size, 1, -1 do
				callback(this.elements[i], i)
			end
		end,

		clear = function(this)
			this.elements = {}
			this.indices = {}
			this.size = 0
		end
	}


	return this
end

return Array