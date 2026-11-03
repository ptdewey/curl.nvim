local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[curl = require("curl")]])
    end,
    post_case = function()
      child.stop()
    end,
  },
})

T["Config"] = MiniTest.new_set()
T["Config"]["setup resets defaults and replaces shell argv"] = function()
  child.lua([[curl.setup({ shell = { "bash", "--custom", "--flag" }, output_split_direction = "horizontal" })]])
  child.lua([[curl.setup({ shell = { "sh", "-eu" } })]])
  MiniTest.expect.equality({ "sh", "-eu" }, child.lua_get([[require("curl.config").get("shell")]]))
  MiniTest.expect.equality("vertical", child.lua_get([[require("curl.config").get("output_split_direction")]]))
  child.lua([[curl.setup()]])
  MiniTest.expect.equality({ "bash", "--noprofile", "--norc" }, child.lua_get([[require("curl.config").get("shell")]]))
end

T["Config"]["commands invoke run and cancel for current source"] = function()
  child.lua([[curl.setup()]])
  child.lua([[
    _G.calls = 0
    require("curl.notebook_runner").start = function(_, callback)
      _G.calls = _G.calls + 1
      return { cancel = function() _G.cancelled = true end }
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "### request", "echo ok" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.cmd("CurlRun")
    vim.cmd("CurlCancel")
  ]])
  MiniTest.expect.equality(1, child.lua_get("_G.calls"))
  MiniTest.expect.equality(true, child.lua_get("_G.cancelled"))
end

T["Config"]["rejects removed configuration"] = function()
  MiniTest.expect.equality(true, child.lua_get([[not pcall(curl.setup, { notebook_mode = true })]]))
end

T["Config"]["rejects false and sparse configuration values"] = function()
  MiniTest.expect.equality(true, child.lua_get([[not pcall(curl.setup, false)]]))
  MiniTest.expect.equality(true, child.lua_get([[not pcall(curl.setup, { shell = false })]]))
  MiniTest.expect.equality(true, child.lua_get([[not pcall(curl.setup, { output_split_direction = false })]]))
  MiniTest.expect.equality(true, child.lua_get([[not pcall(curl.setup, { shell = { [1] = "bash", [3] = "-eu" } })]]))
end

T["Config"]["rejects unknown config lookup"] = function()
  MiniTest.expect.equality(true, child.lua_get([[require("curl.config").get("notebook_mode") == nil]]))
end

T["Config"]["setup registers explicit commands only"] = function()
  child.lua([[curl.setup()]])
  MiniTest.expect.equality(true, child.lua_get([[vim.api.nvim_get_commands({}).CurlRun ~= nil]]))
  MiniTest.expect.equality(true, child.lua_get([[vim.api.nvim_get_commands({}).CurlCancel ~= nil]]))
end

return T
