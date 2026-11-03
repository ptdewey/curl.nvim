local M = {}

OUTPUT_BUF_ID = -1
COMMAND_BUF_ID = -1
TAB_ID = "curl.nvim.tab"
RESULT_BUF_NAME = "Curl output"

local buf_is_open = function(buffer_name)
	local bufnr = vim.fn.bufnr(buffer_name, false)

	return bufnr ~= -1 and vim.fn.bufloaded(bufnr) == 1
end

local close_curl_buffer = function(buffer, force)
	if buffer == -1 or vim.fn.bufexists(buffer) ~= 1 then
		return
	end

	vim.api.nvim_buf_delete(buffer, { force = force })
end

local function find_curl_tab_windid()
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		local success, tab_id = pcall(function() ---@type any,integer
			return vim.api.nvim_tabpage_get_var(tab, "id")
		end)

		if success and tab_id == TAB_ID then
			vim.api.nvim_set_current_tabpage(tab)
			local win_id = vim.api.nvim_tabpage_get_win(tab)
			vim.api.nvim_set_current_win(win_id)
			return win_id
		end
	end
end

local function open_or_goto_curl_tab()
	local config = require("curl.config")
	local open_with = config.get("open_with")

	if open_with == "split" then
		vim.cmd("botright split | wincmd j")
	elseif open_with == "vsplit" then
		vim.cmd("botright vsplit | wincmd l")
	elseif open_with == "buffer" then
		return
	else
		local tab_win_id = find_curl_tab_windid()
		if tab_win_id ~= nil then
			return tab_win_id
		end

		vim.cmd("tabnew")
		vim.api.nvim_tabpage_set_var(0, "id", TAB_ID)
	end
end

local open_command_buffer = function(command_file)
	vim.cmd.edit(command_file)
	local new_bufnr = vim.fn.bufnr(command_file, false)
	local new_win = vim.api.nvim_get_current_win()

	return new_bufnr, new_win
end

local result_open_in_current_tab = function(res_buf_name)
	local buffer = vim.fn.bufnr(res_buf_name, false)

	if not buf_is_open(res_buf_name) then
		return
	end

	local open_windows = vim.api.nvim_tabpage_list_wins(0)
	local windows_containing_buffer = vim.fn.win_findbuf(buffer)

	local set = {}
	for _, win_id in pairs(open_windows) do
		set[win_id] = true ---@type boolean
	end

	for _, win_id in pairs(windows_containing_buffer) do
		if set[win_id] then
			return true
		end
	end

	return false
end

local open_result_buffer = function(called_from_win_id)
	local open_resbuf_name = RESULT_BUF_NAME .. "_" .. called_from_win_id ---@type string

	vim.api.nvim_set_current_win(called_from_win_id)
	if result_open_in_current_tab(open_resbuf_name) then
		return
	end

	local config = require("curl.config")
	local output_split_direction = config.get("output_split_direction")
	local split_cmd = output_split_direction == "horizontal" and "belowright sb" or "vert belowright sb"

	if buf_is_open(open_resbuf_name) then
		local bufnr = vim.fn.bufnr(open_resbuf_name, false)
		vim.cmd(split_cmd .. bufnr .. " | wincmd p")
		OUTPUT_BUF_ID = bufnr
		return
	end

	local new_bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(new_bufnr, open_resbuf_name)
	vim.api.nvim_set_option_value("filetype", "json", { buf = new_bufnr })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = new_bufnr })
	vim.cmd(split_cmd .. new_bufnr .. " | wincmd p")
	OUTPUT_BUF_ID = new_bufnr
end

---sets envs from parsed lines output
---in style like `---var=val`
---@param lines [string]
---@param upper_bound integer | nil
M.setup_buf_vars = function(lines, upper_bound)
	upper_bound = upper_bound or #lines
	for idx = 1, upper_bound do
		local line = lines[idx]
		if not line then
			break
		end
		local k, v = line:match("^%s*%-%-%-%s*([^=]+)=(.*)")
		if k and v then
			vim.env[k] = v
		end
	end
end

M.setup_curl_tab_for_file = function(filename)
	open_or_goto_curl_tab()

	local new_buf_id, current_win = open_command_buffer(filename)
	COMMAND_BUF_ID = new_buf_id
end

M.close_curl_tab = function(force)
	close_curl_buffer(COMMAND_BUF_ID, force)
	close_curl_buffer(OUTPUT_BUF_ID, force)
	COMMAND_BUF_ID, OUTPUT_BUF_ID = -1, -1, -1
end

M.get_command_buffer_and_pos = function()
	local left_buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(left_buf, 0, -1, false)

	local cursor_pos = vim.api.nvim_win_get_cursor(0)[1]

	return cursor_pos, lines
end

M.set_output_buffer_content = function(executed_from_win, content)
	open_result_buffer(executed_from_win)
	vim.api.nvim_buf_set_lines(OUTPUT_BUF_ID, 0, -1, false, content)
end

local notebook_outputs = {}

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
	local buf = notebook_outputs[source_buf]
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		buf = vim.api.nvim_create_buf(false, true)
		notebook_outputs[source_buf] = buf
		vim.api.nvim_buf_set_name(buf, "Curl notebook output " .. source_buf)
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
			return
		end
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
	end)
	if vim.api.nvim_win_is_valid(current_win) then
		vim.api.nvim_set_current_win(current_win)
	end
end

M.cleanup_notebook_output = function(source_buf)
	local buf = notebook_outputs[source_buf]
	notebook_outputs[source_buf] = nil
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		if vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end
	if vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
end

return M
