local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()
local T = new_set({
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

T["notebook API"] = new_set()
T["notebook API"]["clears running feedback and only reports cancellation or failure"] = function()
  child.lua([[
    _G.messages = {}
    vim.notify = function(message, level, opts)
      table.insert(_G.messages, { message = message, level = level, timeout = opts.timeout })
    end
    require("curl.notifications").running = function(title)
      _G.progress = { title = title, active = true }
      return function() _G.progress.active = false end
    end
    require("curl.notebook_runner").start = function(_, callback)
      _G.finish_request = callback
      return { cancel = function() end }
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "### example", "echo ok" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
  ]])
  for _, outcome in ipairs({
    { code = 0, cancelled = false },
    { code = 7, cancelled = false, message = "Request failed (exit 7): example", level = "ERROR" },
    { code = 143, cancelled = true, message = "Request cancelled: example", level = "INFO" },
  }) do
    child.lua([[_G.messages = {}; require("curl").run()]])
    MiniTest.expect.equality(child.lua_get("_G.progress"), { title = "example", active = true })
    child.lua([[
      _G.finish_request({ stdout = "", stderr = "", exit_code = ..., cancelled = select(2, ...) })
    ]], { outcome.code, outcome.cancelled })
    MiniTest.expect.equality(child.lua_get("_G.progress.active"), false)
    if outcome.message then
      MiniTest.expect.equality(child.lua_get("_G.messages[#_G.messages].message"), outcome.message)
      MiniTest.expect.equality(child.lua_get("_G.messages[#_G.messages].level == vim.log.levels." .. outcome.level), true)
    else
      MiniTest.expect.equality(child.lua_get("_G.messages"), {})
    end
  end
end

T["notebook API"]["does not announce running when the shell fails to start"] = function()
  child.lua([[
    _G.messages = {}
    vim.notify = function(message) table.insert(_G.messages, message) end
    require("curl.notebook_runner").start = function() return nil, "shell unavailable" end
    require("curl.notifications").running = function() error("unexpected progress") end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "### example", "echo ok" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    require("curl").run()
  ]])
  MiniTest.expect.equality(child.lua_get("_G.messages"), { "shell unavailable" })
end

T["notebook API"]["updates elapsed seconds during a real request and clears silently on success"] = function()
  child.lua([[
    local notifier = require("mini.notify")
    notifier.setup()
    local messages = {}
    vim.notify = function(message) messages[#messages + 1] = message end
    vim.api.nvim_echo = function() error("unexpected command-line progress") end
    local source = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { "### slow", "sleep 1.2; printf done" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    require("curl").run()
    assert(vim.wait(5000, function()
      return require("tests.helpers").output_buf() ~= -1
    end, 10), "request did not finish")
    local history = notifier.get_all()
    assert(#history == 1, vim.inspect(history))
    local progress = history[1]
    assert(progress.data.source == "curl.nvim")
    assert(progress.msg:find("slow (1s)", 1, true), progress.msg)
    assert(progress.ts_remove ~= nil, "progress notification still active")
    assert(#vim.api.nvim_list_wins() == 2, "notification window still open")
    assert(#messages == 0, vim.inspect(messages))
    vim.wait(150)
    assert(vim.deep_equal(notifier.get_all(), history), "progress continued after completion")
  ]])
end

T["notebook API"]["exports only run cancel and setup and runs without setup"] = function()
  child.lua([[
    local api = require("curl")
    local names = {}
    for key in pairs(api) do names[#names + 1] = key end
    table.sort(names)
    _G.public_names = table.concat(names, ",")
    _G.started_without_setup = 0
    require("curl.notebook_runner").start = function()
      _G.started_without_setup = _G.started_without_setup + 1
      return { cancel = function() end }
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "### request", "echo ok" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    api.run()
  ]])
  MiniTest.expect.equality("cancel,run,setup", child.lua_get("_G.public_names"))
  MiniTest.expect.equality(1, child.lua_get("_G.started_without_setup"))
end

T["notebook API"]["does not modify existing collection files"] = function()
  child.lua([[
    local root = vim.fn.tempname()
    local cache = vim.fs.joinpath(root, "curl_cache")
    vim.fn.mkdir(cache, "p")
    local path = vim.fs.joinpath(cache, "global.curl")
    vim.fn.writefile({ "### saved", "echo preserved" }, path)
    local stdpath = vim.fn.stdpath
    vim.fn.stdpath = function(name)
      if name == "data" then return root end
      return stdpath(name)
    end
    require("curl").setup()
    _G.collection_contents = table.concat(vim.fn.readfile(path), "\n")
    vim.fn.stdpath = stdpath
    vim.fn.delete(root, "rf")
  ]])
  MiniTest.expect.equality("### saved\necho preserved", child.lua_get("_G.collection_contents"))
end

T["notebook API"]["source wipe cancels execution but preserves the shared response"] = function()
  child.lua([[
    local source = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { "### request", "echo ok" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    require("curl.buffers").set_notebook_output(source, { title = "request" }, {
      stdout = "old", stderr = "", exit_code = 0, elapsed = 0,
    })
    _G.cancelled = false
    _G.progress_stopped = false
    require("curl.notifications").running = function()
      return function() _G.progress_stopped = true end
    end
    require("curl.notebook_runner").start = function(_, callback)
      _G.finish_request = callback
      return { cancel = function() _G.cancelled = true end }
    end
    local output = require("tests.helpers").output_buf()
    require("curl").run()
    vim.api.nvim_buf_delete(source, { force = true })
    _G.finish_request({ stdout = "cancelled output", exit_code = 143, cancelled = true })
    _G.output_preserved = vim.api.nvim_buf_is_valid(output)
      and table.concat(vim.api.nvim_buf_get_lines(output, 0, -1, false), "\n"):find("stdout:\nold", 1, true) ~= nil
  ]])
  MiniTest.expect.equality(true, child.lua_get("_G.cancelled"))
  MiniTest.expect.equality(true, child.lua_get("_G.progress_stopped"))
  MiniTest.expect.equality(true, child.lua_get("_G.output_preserved"))
end

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
    require("curl").run()
  ]])
  local received = child.lua_get("_G.received")
  MiniTest.expect.equality(received.cwd, "/tmp/notebook cwd")
  MiniTest.expect.equality(received.setup, "TOKEN=unsaved")
  MiniTest.expect.equality(received.body, "printf '%s' $TOKEN")
  MiniTest.expect.equality(received.script, "TOKEN=unsaved\nprintf '%s' $TOKEN")
end

T["notebook API"]["explicit run never autosaves"] = function()
  child.lua([[
    local config = require("curl.config")
    config.setup()
    local runner = require("curl.notebook_runner")
    _G.started = 0
    runner.start = function(_, callback)
      _G.started = _G.started + 1
      vim.schedule(function() callback({ stdout = "", stderr = "", exit_code = 0, elapsed = 0, cancelled = false }) end)
      return { cancel = function() end }
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "### request", "echo ok" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    require("curl").run()
  ]])
  MiniTest.expect.equality(child.lua_get("_G.started"), 1)
end

T["notebook API"]["runs only selected middle block with shared setup in a real shell"] = function()
  child.lua([[
    local dir = vim.fn.tempname() .. " with spaces"
    vim.fn.mkdir(dir, "p")
    local path = dir .. "/unsaved.sh"
    vim.api.nvim_buf_set_name(0, path)
    vim.bo.filetype = "sh"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "SHARED=setup", "### first", "printf first", "### middle", "printf '%s:%s' \"$SHARED\" middle", "### last", "printf last",
    })
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    require("curl").run()
    vim.wait(3000, function()
      local result = require("tests.helpers").output_buf()
      return result ~= -1 and vim.api.nvim_buf_line_count(result) > 4
    end)
  ]])
  local out = child.lua([[
    local result = require("tests.helpers").output_buf()
    local lines = vim.api.nvim_buf_get_lines(result, 0, -1, false)
    return table.concat(lines, "\n")
  ]])
  MiniTest.expect.no_equality(out:find("setup:middle", 1, true), nil)
  MiniTest.expect.equality(out:find("first", 1, true), nil)
  MiniTest.expect.equality(out:find("last", 1, true), nil)
end

T["notebook API"]["pretty-prints JSON arrays and preserves invalid output and failure streams"] = function()
  child.lua([[
    local buf = vim.api.nvim_get_current_buf()
    require("curl.buffers").set_notebook_output(buf, { title = "array", }, {
      stdout = "[1,{\"ok\":true}]", stderr = "request warning", exit_code = 7, elapsed = 0.5,
    })
  ]])
  local result = child.lua_get([[require("tests.helpers").output_buf()]])
  local text = table.concat(child.api.nvim_buf_get_lines(result, 0, -1, false), "\n")
  MiniTest.expect.no_equality(text:find("  {", 1, true), nil)
  MiniTest.expect.no_equality(text:find("request warning", 1, true), nil)
  MiniTest.expect.no_equality(text:find("Exit code: 7", 1, true), nil)
  child.lua([[
    require("curl.buffers").set_notebook_output(vim.api.nvim_get_current_buf(), { title = "raw" }, {
      stdout = "not json\nraw", stderr = "", exit_code = 0, elapsed = 0, cancelled = false,
    })
  ]])
  text = table.concat(child.api.nvim_buf_get_lines(result, 0, -1, false), "\n")
  MiniTest.expect.no_equality(text:find("not json\nraw", 1, true), nil)
  child.lua([[
    require("curl.buffers").set_notebook_output(vim.api.nvim_get_current_buf(), { title = "empty" }, {
      stdout = "", stderr = "failed before output", exit_code = 2, elapsed = 0.1, cancelled = false,
    })
  ]])
  text = table.concat(child.api.nvim_buf_get_lines(result, 0, -1, false), "\n")
  MiniTest.expect.no_equality(text:find("failed before output", 1, true), nil)
  MiniTest.expect.no_equality(text:find("Exit code: 2", 1, true), nil)
end

return T
