local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[
        _G.now = 0
        _G.echoes = {}
        vim.uv.hrtime = function() return _G.now end
        vim.api.nvim_echo = function(chunks, history)
          assert(not history)
          table.insert(_G.echoes, chunks[1][1])
        end
        vim.schedule_wrap = function(callback)
          return function() _G.pending = callback end
        end
        vim.uv.new_timer = function()
          return {
            start = function(_, delay, interval, callback)
              assert(delay == 100 and interval == 100)
              _G.tick = callback
            end,
            stop = function() _G.timer_stopped = true end,
            close = function() _G.timer_closed = true end,
          }
        end
        _G.notifications = require("curl.notifications")
      ]])
    end,
    post_case = function()
      child.stop()
    end,
  },
})

T["running feedback animates and counts seconds without adding message history"] = function()
  child.lua([[
    _G.stop = _G.notifications.running("example")
    assert(_G.echoes[1] == "⠋ Running request: example (0s)")
    _G.now = 1100000000
    _G.tick()
    _G.pending()
    assert(_G.echoes[2] == "⠙ Running request: example (1s)")
    _G.tick()
    _G.stop()
    assert(_G.timer_stopped and _G.timer_closed)
    assert(_G.echoes[3] == "")
    _G.pending()
    _G.stop()
    assert(#_G.echoes == 3, vim.inspect(_G.echoes))
  ]])
end

T["stopping one request keeps feedback for other running requests"] = function()
  child.lua([[
    local stop_first = _G.notifications.running("first")
    _G.now = 2000000000
    local stop_second = _G.notifications.running("second")
    local message = _G.echoes[#_G.echoes]
    assert(message:find("first (2s)", 1, true), message)
    assert(message:find("second (0s)", 1, true), message)
    stop_first()
    assert(not _G.timer_closed)
    message = _G.echoes[#_G.echoes]
    assert(not message:find("first", 1, true), message)
    assert(message:find("second (0s)", 1, true), message)
    stop_first()
    stop_second()
    assert(_G.timer_closed)
    assert(_G.echoes[#_G.echoes] == "")
  ]])
end

return T
