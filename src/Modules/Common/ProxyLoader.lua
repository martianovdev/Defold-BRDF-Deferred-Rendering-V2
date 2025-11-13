local ProxyLoader = {}

function ProxyLoader:new()
	local this = {
		init = function(this)
			this.data_by_collection_name = {}
			this.manifest = liveupdate.get_current_manifest()
			this.is_desktop = sys.get_sys_info().system_name == "Windows" or 
			sys.get_sys_info().system_name == "Mac OS X" or
			sys.get_sys_info().system_name == "Linux"
		end,

		callback_store_resource = function(this, hexdigest, status)
			if status == true then
				print("Successfully stored resource: " .. hexdigest)
			else
				print("Failed to store resource: " .. hexdigest)
			end
		end,

		load_proxy = function(this, properties)
			local proxy_url = properties.proxy_url
			local collection_name = properties.collection_name
			local init_data = properties.init_data

			local collection_name_hash = hash(collection_name)
			this.data_by_collection_name[collection_name_hash] = init_data

			local resources = collectionproxy.missing_resources(proxy_url)

			-- If no missing resources, load proxy immediately
			if #resources == 0 then
				msg.post(proxy_url, "load")
				return
			end

			-- Counter of remaining resources to load
			local pending_resources = #resources

			for _, resource_hash in ipairs(resources) do
				if this.is_desktop then
					-- For desktop version read files directly from disk
					local path = sys.get_application_path() .. "/data/" .. resource_hash
					local file = io.open(path, "rb")
					if file then
						local content = file:read("*a")
						file:close()
						-- liveupdate.store_archive(path, function(self2, _path, status)
						-- 	this:callback_store_resource(_path, status)
						-- 	pending_resources = pending_resources - 1
						-- 	if pending_resources == 0 then
						-- 		msg.post(proxy_url, "load")
						-- 	end
						-- end)
						liveupdate.store_resource(this.manifest, content, resource_hash, function(self2, hexdigest, status)
							this:callback_store_resource(hexdigest, status)
							pending_resources = pending_resources - 1
							if pending_resources == 0 then
								msg.post(proxy_url, "load")
							end
						end)
					else
						print("Failed to read resource file: " .. path)
						pending_resources = pending_resources - 1
						if pending_resources == 0 then
							msg.post(proxy_url, "load")
						end
					end
				else
					-- For mobile platforms load via HTTP
					local baseurl = "/data/"
					http.request(baseurl .. resource_hash, "GET", function(self1, id, response)
						if response.status == 200 then
							liveupdate.store_resource(this.manifest, response.response, resource_hash, function(self2, hexdigest, status)
								this:callback_store_resource(hexdigest, status)
								pending_resources = pending_resources - 1
								if pending_resources == 0 then
									msg.post(proxy_url, "load")
								end
							end)
						else
							print("Failed to download resource: " .. resource_hash)
							pending_resources = pending_resources - 1
							if pending_resources == 0 then
								msg.post(proxy_url, "load")
							end
						end
					end)
				end
			end
		end,

		get_init_data = function(this)
			local url = msg.url()
			return this.data_by_collection_name[url.socket]
		end
	}
	this:init()
	return this
end

return ProxyLoader:new()