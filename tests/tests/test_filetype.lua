local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[require("curl")]])
    end,
    post_case = function()
      child.stop()
    end,
  },
})

T["does not register automatic filetype, keymaps, or execution"] = function()
  child.cmd("enew")
  child.cmd("file ordinary.sh")
  MiniTest.expect.no_equality(child.bo.filetype, "curl")
  MiniTest.expect.equality(#child.api.nvim_buf_get_keymap(0, "n"), 0)
  MiniTest.expect.equality(true, child.lua_get([[vim.api.nvim_get_commands({}).CurlRun == nil]]))
  child.lua([[require("curl").setup()]])
  local commands = child.api.nvim_get_commands({})
  MiniTest.expect.equality(true, commands.CurlRun ~= nil)
  MiniTest.expect.equality(true, commands.CurlCancel ~= nil)
  MiniTest.expect.equality(true, child.lua_get([[vim.api.nvim_get_commands({}).CurlOpen == nil]]))
  MiniTest.expect.equality(true, child.lua_get([[vim.api.nvim_get_commands({}).CurlOpenCollection == nil]]))
end

return T
