local M = {}
local notify = require("curl.notifications")

---comment
---@param global boolean
---@return string
local function get_custom_dir(global)
	if global then
		return "custom"
	else
		local workspace_path = vim.fn.getcwd()
		local unique = vim.fn.fnamemodify(workspace_path, ":t") .. "_" .. vim.fn.sha256(workspace_path):sub(1, 8) ---@type string
		return "scopedcustom/" .. unique
	end
end

local curl_cache_dir = function(custom_dir)
	local cache_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "curl_cache")

	if custom_dir then
		cache_dir = vim.fs.joinpath(cache_dir, custom_dir)
	end

	if vim.fn.mkdir(cache_dir, "p") ~= 1 and vim.uv.fs_stat(cache_dir) == nil then
		notify.error("Error creating collection: could not create directory : " .. cache_dir)
	end

	return cache_dir
end

---@param filename string
---@return string
M.load_custom_command_file = function(filename, global)
	local custom_dir = get_custom_dir(global)
	local cache_dir = curl_cache_dir(custom_dir)

	local curl_filename = filename .. ".curl"
	return vim.fs.joinpath(cache_dir, curl_filename)
end

---@return string
M.load_global_command_file = function()
	local cache_dir = curl_cache_dir()

	return vim.fs.joinpath(cache_dir, "global.curl")
end

---@return string
M.load_command_file = function()
	local workspace_path = vim.fn.getcwd()
	local cache_dir = curl_cache_dir()

	local unique_id = vim.fn.fnamemodify(workspace_path, ":t") .. "_" .. vim.fn.sha256(workspace_path):sub(1, 8) ---@type string
	local new_file_name = unique_id .. ".curl"

	local old_cache_file = vim.fs.joinpath(cache_dir, vim.fn.sha256(workspace_path))
	local new_cache_file = vim.fs.joinpath(cache_dir, new_file_name)

	if vim.uv.fs_stat(old_cache_file) then
		if vim.uv.fs_stat(new_cache_file) == nil then
			os.rename(old_cache_file, new_cache_file)
		else
			local archive_file = vim.fs.joinpath(cache_dir, vim.fn.sha256(workspace_path) .. ".archive")
			os.rename(old_cache_file, archive_file)
		end
	end

	return new_cache_file
end

---@param global boolean set to true to search global scorep
---@return table Table of collection in the given scope
M.get_collections = function(global)
	local collection_dir = curl_cache_dir(get_custom_dir(global))

	local files = {}
	for name, file_type in vim.fs.dir(collection_dir) do
		if file_type == "file" then
			table.insert(files, vim.fn.fnamemodify(name, ":r"))
		end
	end

	return files
end

return M
