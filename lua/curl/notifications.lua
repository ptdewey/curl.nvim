local M = {}

local standard_opts = { timeout = 3000, title = "curl.nvim" }
local running = {}
local timer
local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function show_progress()
	local messages = {}
	local now = vim.uv.hrtime()
	for _, request in ipairs(running) do
		local elapsed = (now - request.started) / 1e9
		local frame = frames[math.floor(elapsed * 10) % #frames + 1]
		messages[#messages + 1] = string.format("%s Running request: %s (%ds)", frame, request.title, math.floor(elapsed))
	end
	vim.api.nvim_echo({ { table.concat(messages, " | "), "Normal" } }, false, {})
end

M.running = function(title)
	local request = { title = title, started = vim.uv.hrtime() }
	running[#running + 1] = request
	if not timer then
		timer = assert(vim.uv.new_timer())
		timer:start(100, 100, vim.schedule_wrap(function()
			if timer then
				show_progress()
			end
		end))
	end
	show_progress()
	return function()
		for index, active in ipairs(running) do
			if active == request then
				table.remove(running, index)
				if #running == 0 then
					timer:stop()
					timer:close()
					timer = nil
				end
				show_progress()
				return
			end
		end
	end
end

M.error = function(message)
	vim.notify(message, vim.log.levels.ERROR, standard_opts)
end

M.info = function(message)
	vim.notify(message, vim.log.levels.INFO, standard_opts)
end

return M
