local M = {}

local standard_opts = { timeout = 3000, title = "curl.nvim" }
local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

M.running = function(title)
	local notifier = rawget(_G, "MiniNotify")
	if not notifier then
		M.info("Running request: " .. title)
		return function() end
	end
	local started = vim.uv.hrtime()
	local function message()
		local elapsed = (vim.uv.hrtime() - started) / 1e9
		local frame = frames[math.floor(elapsed * 10) % #frames + 1]
		return string.format("curl.nvim: %s Running request: %s (%ds)", frame, title, math.floor(elapsed))
	end
	local timer = assert(vim.uv.new_timer())
	local id = notifier.add(message(), "INFO", "DiagnosticInfo", { source = "curl.nvim" })
	local active = true
	local function stop()
		if not active then
			return
		end
		active = false
		timer:stop()
		timer:close()
		notifier.remove(id)
	end
	timer:start(100, 100, vim.schedule_wrap(function()
		if not active then
			return
		end
		local notification = notifier.get(id)
		if not notification or notification.ts_remove then
			stop()
			return
		end
		notifier.update(id, { msg = message() })
	end))
	return stop
end

M.error = function(message)
	vim.notify(message, vim.log.levels.ERROR, standard_opts)
end

M.info = function(message)
	vim.notify(message, vim.log.levels.INFO, standard_opts)
end

return M
