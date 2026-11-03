local M = {}

local config = require("curl.config")
local buffers = require("curl.buffers")
local notify = require("curl.notifications")
local notebook = require("curl.notebook")
local notebook_runner = require("curl.notebook_runner")

local notebook_runs = {}

vim.api.nvim_create_autocmd("BufWipeout", {
  callback = function(event)
    local handle = notebook_runs[event.buf]
    if handle then
      handle.cancel()
      notebook_runs[event.buf] = nil
    end
    buffers.cleanup_notebook_output(event.buf)
  end,
})

function M.run()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local extracted, err = notebook.extract(lines, cursor)
  if not extracted then
    notify.error(err)
    return
  end
  if notebook_runs[bufnr] then
    notify.error("A notebook request is already running for this buffer")
    return
  end
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local cwd = filename ~= "" and vim.fn.fnamemodify(filename, ":p:h") or vim.fn.getcwd()
  local handle, start_error = notebook_runner.start({
    script = extracted.script,
    setup = extracted.setup,
    body = extracted.body,
    cwd = cwd,
    shell = vim.deepcopy(config.get("shell")),
  }, function(result)
    notebook_runs[bufnr] = nil
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    buffers.set_notebook_output(bufnr, extracted, cwd, result)
  end)
  if not handle then
    notify.error(start_error or "Unable to start notebook shell")
    return
  end
  notebook_runs[bufnr] = handle
  return handle
end

function M.cancel(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local handle = notebook_runs[bufnr]
  if not handle then
    notify.error("No notebook request is running for this buffer")
    return
  end
  handle.cancel()
end

return M
