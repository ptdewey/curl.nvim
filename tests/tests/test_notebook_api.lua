local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[require("curl").setup({ notebook_mode = true })]])
    end,
    post_case = function()
      child.stop()
    end,
  },
})

T["notebook API"] = new_set()
T["notebook API"]["executes unsaved selected source and preserves cwd with spaces"] = function()
  child.lua([[
    local runner = require("curl.notebook_runner")
    _G.received = nil
    runner.start = function(options, callback)
      _G.received = options
      vim.schedule(function() callback({ stdout = "plain output", stderr = "warning", exit_code = 7, elapsed = 0.25, cancelled = false }) end)
      return { cancel = function() end }
    end
    vim.api.nvim_buf_set_name(0, "/tmp/notebook cwd/unsaved.curl")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "TOKEN=unsaved", "### chosen", "printf '%s' $TOKEN" })
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    require("curl.api").execute_notebook()
  ]])
  local received = child.lua_get("_G.received")
  MiniTest.expect.equality(received.cwd, "/tmp/notebook cwd")
  MiniTest.expect.equality(received.setup, "TOKEN=unsaved")
  MiniTest.expect.equality(received.body, "printf '%s' $TOKEN")
  MiniTest.expect.equality(received.script, "TOKEN=unsaved\nprintf '%s' $TOKEN")
end

T["notebook API"]["explicit command runs despite notebook mode being disabled and never autosaves"] = function()
  child.lua([[
    local config = require("curl.config")
    config.set("notebook_mode", false)
    local runner = require("curl.notebook_runner")
    _G.started = 0
    runner.start = function(_, callback)
      _G.started = _G.started + 1
      vim.schedule(function() callback({ stdout = "", stderr = "", exit_code = 0, elapsed = 0, cancelled = false }) end)
      return { cancel = function() end }
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "### request", "echo ok" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    require("curl.api").execute_notebook()
  ]])
  MiniTest.expect.equality(child.lua_get("_G.started"), 1)
end

T["notebook API"]["runs only selected middle block with shared setup in a real shell"] = function()
  child.lua([[
    local dir = vim.fn.tempname() .. " with spaces"
    vim.fn.mkdir(dir, "p")
    local path = dir .. "/unsaved.curl"
    vim.api.nvim_buf_set_name(0, path)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "SHARED=setup", "### first", "printf first", "### middle", "printf '%s:%s' \"$SHARED\" middle", "### last", "printf last",
    })
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    require("curl.api").execute_notebook()
    vim.wait(3000, function()
      local result = vim.fn.bufnr("Curl notebook output " .. vim.api.nvim_get_current_buf())
      return result ~= -1 and vim.api.nvim_buf_line_count(result) > 4
    end)
  ]])
  local out = child.lua([[
    local source = vim.api.nvim_get_current_buf()
    local result = vim.fn.bufnr("Curl notebook output " .. source)
    local lines = vim.api.nvim_buf_get_lines(result, 0, -1, false)
    return table.concat(lines, "\n")
  ]])
  MiniTest.expect.no_equality(out:find("setup:middle", 1, true), nil)
  MiniTest.expect.equality(out:find("first", 1, true), nil)
  MiniTest.expect.equality(out:find("last", 1, true), nil)
end

T["notebook API"]["execute_curl dispatches notebook first when enabled"] = function()
  child.lua([[
    require("curl.config").set("notebook_mode", true)
    local runner = require("curl.notebook_runner")
    _G.started = 0
    runner.start = function(_, callback)
      _G.started = _G.started + 1
      vim.schedule(function() callback({ stdout = "", stderr = "", exit_code = 0, elapsed = 0, cancelled = false }) end)
      return { cancel = function() end }
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "### request", "echo ok" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    require("curl.api").execute_curl()
  ]])
  MiniTest.expect.equality(child.lua_get("_G.started"), 1)
end

T["notebook API"]["pretty-prints JSON arrays and preserves invalid output and failure streams"] = function()
  child.lua([[
    local buf = vim.api.nvim_get_current_buf()
    require("curl.buffers").set_notebook_output(buf, { title = "array", }, "/tmp", {
      stdout = "[1,{\"ok\":true}]", stderr = "request warning", exit_code = 7, elapsed = 0.5,
    })
  ]])
  local source = child.api.nvim_get_current_buf()
  local result = child.fn.bufnr("Curl notebook output " .. source)
  local text = table.concat(child.api.nvim_buf_get_lines(result, 0, -1, false), "\n")
  MiniTest.expect.no_equality(text:find("  {", 1, true), nil)
  MiniTest.expect.no_equality(text:find("request warning", 1, true), nil)
  MiniTest.expect.no_equality(text:find("Status: 7", 1, true), nil)
  child.lua([[
    require("curl.buffers").set_notebook_output(vim.api.nvim_get_current_buf(), { title = "raw" }, "/tmp", {
      stdout = "not json\nraw", stderr = "", exit_code = 0, elapsed = 0, cancelled = false,
    })
  ]])
  text = table.concat(child.api.nvim_buf_get_lines(result, 0, -1, false), "\n")
  MiniTest.expect.no_equality(text:find("not json\nraw", 1, true), nil)
  child.lua([[
    require("curl.buffers").set_notebook_output(vim.api.nvim_get_current_buf(), { title = "empty" }, "/tmp", {
      stdout = "", stderr = "failed before output", exit_code = 2, elapsed = 0.1, cancelled = false,
    })
  ]])
  text = table.concat(child.api.nvim_buf_get_lines(result, 0, -1, false), "\n")
  MiniTest.expect.no_equality(text:find("failed before output", 1, true), nil)
  MiniTest.expect.no_equality(text:find("Status: 2", 1, true), nil)
end

T["notebook API"]["execute_curl retains legacy path unless explicitly enabled"] = function()
  child.lua([[
    require("curl.config").set("notebook_mode", false)
    _G.legacy_called = false
    require("curl.parser").parse_curl_command = function() _G.legacy_called = true; return "" end
    require("curl.api").execute_curl()
  ]])
  MiniTest.expect.equality(child.lua_get("_G.legacy_called"), true)
end

return T
