local new_set = MiniTest.new_set

local api = require("curl.api")
local buffers = require("curl.buffers")

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      -- Restart child process with custom 'init.lua' script
      child.restart({ "-u", "scripts/minimal_init.lua" })
      -- Load tested plugin
      child.lua([[M = require('curl').setup({})]])
    end,
    after_case = function()
      api.close_curl_tab(true)
    end,
  },
})

T["api"] = new_set()
T["api"]["can curl something"] = function()
  local fixture = vim.fn.tempname()
  vim.fn.writefile({ [[{"userId":1,"id":1,"title":"delectus aut autem","completed":false}]] }, fixture)
  local curl_command = "curl " .. vim.fn.shellescape("file://" .. fixture)

  child.lua([[
    require("curl").open_curl_tab()
  ]])
  child.api.nvim_buf_set_lines(0, 0, -1, false, { curl_command })

  child.type_keys("gg")
  child.lua([[
    require("curl").execute_curl()
  ]])

  child.lua([[
    assert(vim.wait(5000, function()
      return OUTPUT_BUF_ID ~= -1 and vim.api.nvim_buf_is_valid(OUTPUT_BUF_ID)
    end, 10), "response buffer was not opened")
  ]])
  vim.fn.delete(fixture)
  child.cmd("wincmd l")
  local output = child.api.nvim_buf_get_lines(0, 0, -1, false)

  local expected_output = [[{
  "userId": 1,
  "id": 1,
  "title": "delectus aut autem",
  "completed": false
}]]

  MiniTest.expect.equality(table.concat(output, "\n"), expected_output)
end

T["api"]["can open custom buffer"] = function()
  local custom_name = "sauron"
  api.open_scoped_collection(custom_name)

  local bufname = vim.api.nvim_buf_get_name(0)
  MiniTest.expect.no_equality(bufname:find(custom_name), nil)

  api.close_curl_tab()
  local new_bufname = vim.api.nvim_buf_get_name(0)
  MiniTest.expect.equality(new_bufname:find(custom_name), nil, "Buffer should be closed")
end

T["api"]["can open custom global buffer"] = function()
  local custom_name = "frodo"
  api.open_global_collection(custom_name)

  local bufname = vim.api.nvim_buf_get_name(0)
  MiniTest.expect.no_equality(bufname:find(custom_name), nil, "Global custom buffer should be open")

  api.close_curl_tab()
  local new_bufname = vim.api.nvim_buf_get_name(0)
  MiniTest.expect.equality(new_bufname:find(custom_name), nil, "Buffer should be closed")
end

T["api"]["can open global buffer"] = function()
  api.open_global_tab()

  local bufname = vim.api.nvim_buf_get_name(0)
  MiniTest.expect.no_equality(bufname:find("global"), nil)

  api.close_curl_tab()
  local new_bufname = vim.api.nvim_buf_get_name(0)
  MiniTest.expect.equality(new_bufname:find("global"), nil)
end
return T
