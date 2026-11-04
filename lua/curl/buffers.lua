local M = {}

local notebook_output

-- :restart writes a session, which otherwise restores nofile output splits.
if vim.fn.exists("##SessionWritePre") == 1 then
	vim.api.nvim_create_autocmd("SessionWritePre", {
		group = vim.api.nvim_create_augroup("CurlNotebookOutput", { clear = true }),
		callback = function()
			local buf = notebook_output
			if not buf or not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			for _, win in ipairs(vim.fn.win_findbuf(buf)) do
				-- The last window cannot close; deleting its buffer below is enough.
				pcall(vim.api.nvim_win_close, win, true)
			end
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
			notebook_output = nil
		end,
	})
end

local function clean_output(text)
	return (text:gsub("\27%][^\7\27]*\7", "")
		:gsub("\27%][^\7\27]*\27\\", "")
		:gsub("\27%[[0-?]*[ -/]*[@-~]", "")
		:gsub("\r\n", "\n")
		:gsub("\r", "\n"))
end

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

local function set_notebook_syntax(buf, is_json, body_start, stderr_start)
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
		vim.cmd(string.format([[syntax match CurlNotebookMetadata /\%%<%dl.*/]], body_start))
		if stderr_start then
			vim.cmd(string.format([[syntax match CurlNotebookStderr /\%%>%dl.*/]], stderr_start - 1))
		end
	end)
end

local function response_status(body)
	local status
	while true do
		local current = body:match("^HTTP/%d[%d.]* (%d%d%d[^\n]*)\n")
		local header_end = body:find("\n\n", 1, true)
		if not current or not header_end then
			return status
		end
		status = current
		body = body:sub(header_end + 2)
	end
end

M.set_notebook_output = function(source_buf, extracted, result)
	local buf = notebook_output
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		buf = vim.api.nvim_create_buf(false, true)
		notebook_output = buf
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
		vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	end
	local body = clean_output(result.stdout or "")
	local stderr = clean_output(result.stderr or "")
	local status = response_status(body)
	local is_json = false
	if body ~= "" then
		body, is_json = pretty_json(body)
	end
	local lines = {
		"Request: " .. (extracted.title ~= "" and extracted.title or "(untitled)"),
	}
	for _, request in ipairs(result.requests or {}) do
		for _, url in ipairs(request.urls) do
			vim.list_extend(lines, vim.split("URL: " .. clean_output(url), "\n", { plain = true }))
		end
		if #request.headers > 0 then
			table.insert(lines, "Headers:")
			for _, header in ipairs(request.headers) do
				for _, line in ipairs(vim.split(clean_output(header), "\n", { plain = true })) do
					table.insert(lines, "  " .. line)
				end
			end
		end
	end
	if status then
		table.insert(lines, "Status: " .. status)
	end
	if result.cancelled then
		table.insert(lines, "Cancelled")
	elseif result.exit_code and result.exit_code ~= 0 then
		table.insert(lines, "Exit code: " .. result.exit_code)
	end
	table.insert(lines, string.format("Elapsed: %.3fs", result.elapsed or 0))
	table.insert(lines, "")
	table.insert(lines, "stdout:")
	local body_start = #lines + 1
	vim.list_extend(lines, vim.split(body, "\n", { plain = true }))
	local stderr_start
	if stderr ~= "" then
		stderr_start = #lines + 1
		table.insert(lines, "")
		table.insert(lines, "stderr:")
		vim.list_extend(lines, vim.split(stderr, "\n", { plain = true }))
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	set_notebook_syntax(buf, is_json, body_start, stderr_start)
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
