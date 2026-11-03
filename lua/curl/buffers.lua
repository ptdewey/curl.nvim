local M = {}

local notebook_output

local function pretty_json(text)
	local ok = pcall(vim.json.decode, text)
	if not ok then
		return text, false
	end
	local output, depth = {}, 0
	local quoted, escaped = false, false
	local function append(value)
		output[#output + 1] = value
	end
	for index = 1, #text do
		local char = text:sub(index, index)
		if quoted then
			append(char)
			if escaped then
				escaped = false
			elseif char == "\\" then
				escaped = true
			elseif char == '"' then
				quoted = false
			end
		elseif char == '"' then
			quoted = true
			append(char)
		elseif char == "{" or char == "[" then
			append(char)
			local next_index = index + 1
			while next_index <= #text and text:sub(next_index, next_index):match("%s") do
				next_index = next_index + 1
			end
			local close = char == "{" and "}" or "]"
			if text:sub(next_index, next_index) ~= close then
				depth = depth + 1
				append("\n" .. string.rep("  ", depth))
			end
		elseif char == "}" or char == "]" then
			local previous = #output > 0 and output[#output] or ""
			local close = char == "}" and "{" or "["
			if previous ~= close then
				depth = depth - 1
				append("\n" .. string.rep("  ", depth))
			end
			append(char)
		elseif char == "," then
			append(",\n" .. string.rep("  ", depth))
		elseif char == ":" then
			append(": ")
		elseif not char:match("%s") then
			append(char)
		end
	end
	return table.concat(output), true
end

local function set_notebook_syntax(buf, is_json, stderr_start)
	local filetype = is_json and "json" or "text"
	vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })
	vim.api.nvim_set_option_value("syntax", filetype, { buf = buf })
	if not is_json then
		return
	end
	vim.api.nvim_set_hl(0, "CurlNotebookMetadata", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "CurlNotebookStderr", { link = "Comment", default = true })
	vim.api.nvim_buf_call(buf, function()
		vim.cmd("silent! syntax clear CurlNotebookMetadata CurlNotebookStderr")
		vim.cmd([[syntax match CurlNotebookMetadata /\%<7l.*/]])
		if stderr_start then
			vim.cmd(string.format([[syntax match CurlNotebookStderr /\%%>%dl.*/]], stderr_start - 1))
		end
	end)
end

M.set_notebook_output = function(source_buf, extracted, cwd, result)
	local buf = notebook_output
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		buf = vim.api.nvim_create_buf(false, true)
		notebook_output = buf
		vim.api.nvim_buf_set_name(buf, "Curl notebook output")
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
		vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
	end
	local body = result.stdout or ""
	local is_json = false
	if body ~= "" then
		body, is_json = pretty_json(body)
	end
	local status = result.cancelled and "cancelled" or tostring(result.exit_code)
	local lines = {
		"Request: " .. (extracted.title ~= "" and extracted.title or "(untitled)"),
		"Directory: " .. cwd,
		"Status: " .. status,
		string.format("Elapsed: %.3fs", result.elapsed or 0),
		"",
		"stdout:",
	}
	vim.list_extend(lines, vim.split(body, "\n", { plain = true }))
	local stderr_start
	if result.stderr and result.stderr ~= "" then
		stderr_start = #lines + 1
		table.insert(lines, "")
		table.insert(lines, "stderr:")
		vim.list_extend(lines, vim.split(result.stderr, "\n", { plain = true }))
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	set_notebook_syntax(buf, is_json, stderr_start)
	local result_windows = vim.fn.win_findbuf(buf)
	for _, win in ipairs(result_windows) do
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_set_option_value("spell", false, { win = win })
		end
	end
	if #result_windows > 0 then
		return
	end
	local current_win = vim.api.nvim_get_current_win()
	local source_windows = vim.fn.win_findbuf(source_buf)
	local target_win = source_windows[1]
	if not target_win or not vim.api.nvim_win_is_valid(target_win) then
		target_win = current_win
	end
	if not vim.api.nvim_win_is_valid(target_win) then
		return
	end
	vim.api.nvim_win_call(target_win, function()
		local direction = require("curl.config").get("output_split_direction")
		vim.cmd(direction == "vertical" and "belowright vsplit" or "belowright split")
		vim.api.nvim_win_set_buf(0, buf)
		vim.api.nvim_set_option_value("spell", false, { win = 0 })
	end)
	if vim.api.nvim_win_is_valid(current_win) then
		vim.api.nvim_set_current_win(current_win)
	end
end

return M
