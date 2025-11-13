local IDManager = {}
function IDManager:new()
	local this = {
		nextID = 1,
		freeIDs = {},

		get = function(this)
			if #this.freeIDs > 0 then
				return table.remove(this.freeIDs)
			else
				local id = this.nextID
				this.nextID = this.nextID + 1
				return id
			end
		end,

		free = function(this, id)
			table.insert(this.freeIDs, id)
		end
	}

	return this
end

return IDManager