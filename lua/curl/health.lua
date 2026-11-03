local M = {}

function M.check()
	vim.health.start("Notebook execution")
	local shell = require("curl.config").get("shell")[1]
	if vim.fn.executable(shell) == 1 then
		vim.health.ok("Configured shell available: " .. shell)
	else
		vim.health.error("Configured shell not found: " .. shell)
	end
	if vim.fn.executable("curl") == 1 then
		vim.health.ok("curl available on the editor's PATH")
	else
		vim.health.warn("curl not found on the editor's PATH; provide it in notebook setup if requests use it")
	end
end

return M
