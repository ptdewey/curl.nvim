local M = {}

local notify = require("curl.notifications")

--- Run jq synchronously using Neovim's native process API.
---@param unformatted_json string
---@return table
local function run_jq(unformatted_json)
	local result = vim.system({ "jq", "." }, { stdin = unformatted_json }):wait()
	if result.code ~= 0 then
		notify.error("Failed to parse JSON")
		return { unformatted_json }
	end

	local output = vim.split(result.stdout or "", "\n", { plain = true })
	if output[#output] == "" then
		table.remove(output)
	end
	return output
end

local function trim(s)
	local from = s:match("^%s*()")
	return from > #s and "" or s:match(".*%S", from)
end

local function is_json_start(line)
	return line:match("^[%[%{]") ~= nil
end

local function extract_json(output_lines)
	local header_lines = {}
	local json_string = nil

	for _, line in ipairs(output_lines) do
		local trimmed_line = trim(line)
		if is_json_start(trimmed_line) then
			json_string = trimmed_line
			break
		end
		table.insert(header_lines, trimmed_line)
	end

	return header_lines, json_string
end

---
---@param curl_standard_out string
---@return table
M.parse_curl_output = function(curl_standard_out)
	if is_json_start(curl_standard_out) then
		return run_jq(curl_standard_out)
	end

	local output_table = vim.split(curl_standard_out, "\r")
	local header_lines, json_string = extract_json(output_table)

	if json_string == nil then
		return output_table
	end

	local json_lines = run_jq(json_string)
	table.move(json_lines, 1, #json_lines, #header_lines + 1, header_lines)
	return header_lines
end
return M
