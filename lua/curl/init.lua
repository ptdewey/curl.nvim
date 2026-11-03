local M = {}
local api = require("curl.api")

function M.run()
  return api.run()
end

function M.cancel(bufnr)
  return api.cancel(bufnr)
end

function M.setup(opts)
  require("curl.config").setup(opts)
  vim.api.nvim_create_user_command("CurlRun", M.run, {
    desc = "Run the notebook request under the cursor",
  })
  vim.api.nvim_create_user_command("CurlCancel", function()
    M.cancel()
  end, {
    desc = "Cancel the notebook request for this buffer",
  })
end

return M
