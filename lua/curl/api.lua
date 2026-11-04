local M = {}

local config = require("curl.config")
local buffers = require("curl.buffers")
local notify = require("curl.notifications")
local notebook = require("curl.notebook")
local notebook_runner = require("curl.notebook_runner")

local notebook_runs = {}

vim.api.nvim_create_autocmd("BufWipeout", {
  callback = function(event)
    local run = notebook_runs[event.buf]
    if run then
      run.stop_progress()
      run.handle.cancel()
      notebook_runs[event.buf] = nil
    end
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
  local title = extracted.title ~= "" and extracted.title or "(untitled)"
  local stop_progress
  local handle, start_error = notebook_runner.start({
    script = extracted.script,
    setup = extracted.setup,
    body = extracted.body,
    cwd = cwd,
    shell = vim.deepcopy(config.get("shell")),
  }, function(result)
    if stop_progress then
      stop_progress()
    end
    notebook_runs[bufnr] = nil
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    buffers.set_notebook_output(bufnr, extracted, result)
    if result.cancelled then
      notify.info("Request cancelled: " .. title)
    elseif result.exit_code ~= 0 then
      notify.error(string.format("Request failed (exit %s): %s", result.exit_code, title))
    end
  end)
  if not handle then
    notify.error(start_error or "Unable to start notebook shell")
    return
  end
  stop_progress = notify.running(title)
  notebook_runs[bufnr] = { handle = handle, stop_progress = stop_progress }
  return handle
end

function M.cancel(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local run = notebook_runs[bufnr]
  if not run then
    notify.error("No notebook request is running for this buffer")
    return
  end
  run.handle.cancel()
end

return M
