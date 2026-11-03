local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[
        _G.now = 0
        _G.events = {}
        _G.items = {}
        _G.timers = {}
        vim.uv.hrtime = function() return _G.now end
        vim.api.nvim_echo = function() error("unexpected command-line progress") end
        vim.schedule_wrap = function(callback)
          return function() _G.pending = callback end
        end
        vim.uv.new_timer = function()
          local timer = {
            start = function(self, delay, interval, callback)
              assert(delay == 100 and interval == 100)
              self.tick = callback
            end,
            stop = function(self) self.stopped = true end,
            close = function(self) self.closed = true end,
          }
          table.insert(_G.timers, timer)
          return timer
        end
        _G.MiniNotify = {
          add = function(message, level, highlight, data)
            assert(level == "INFO" and data.source == "curl.nvim")
            local id = #_G.events + 1
            _G.items[id] = { msg = message }
            table.insert(_G.events, { kind = "add", id = id, message = message })
            return id
          end,
          update = function(id, notification)
            table.insert(_G.events, { kind = "update", id = id, message = notification.msg })
          end,
          get = function(id) return _G.items[id] end,
          remove = function(id)
            table.insert(_G.events, { kind = "remove", id = id })
          end,
        }
        _G.notifications = require("curl.notifications")
      ]])
    end,
    post_case = function()
      child.stop()
    end,
  },
})

T["running feedback updates one notification with a spinner and elapsed seconds"] = function()
  child.lua([[
    local stop = _G.notifications.running("example")
    assert(_G.events[1].message == "curl.nvim: ⠋ Running request: example (0s)")
    _G.now = 1100000000
    _G.timers[1].tick()
    _G.pending()
    assert(_G.events[2].kind == "update" and _G.events[2].id == _G.events[1].id)
    assert(_G.events[2].message == "curl.nvim: ⠙ Running request: example (1s)")
    _G.timers[1].tick()
    stop()
    assert(_G.timers[1].stopped and _G.timers[1].closed)
    assert(_G.events[3].kind == "remove" and _G.events[3].id == _G.events[1].id)
    _G.pending()
    stop()
    assert(#_G.events == 3, vim.inspect(_G.events))
  ]])
end

T["concurrent requests have independent notifications and timers"] = function()
  child.lua([[
    local stop_first = _G.notifications.running("first")
    _G.now = 2000000000
    local stop_second = _G.notifications.running("second")
    assert(_G.events[1].id ~= _G.events[2].id)
    stop_first()
    assert(_G.events[3].kind == "remove" and _G.events[3].id == _G.events[1].id)
    assert(not _G.timers[2].closed)
    _G.now = 3100000000
    _G.timers[2].tick()
    _G.pending()
    assert(_G.events[4].id == _G.events[2].id)
    assert(_G.events[4].message:find("second (1s)", 1, true))
    stop_second()
    assert(_G.timers[2].closed)
    assert(_G.events[5].kind == "remove" and _G.events[5].id == _G.events[2].id)
  ]])
end

T["dismissing a notification stops updates without bringing it back"] = function()
  child.lua([[
    local stop = _G.notifications.running("example")
    _G.items[_G.events[1].id].ts_remove = 1
    _G.timers[1].tick()
    _G.pending()
    assert(_G.timers[1].closed)
    assert(_G.events[2].kind == "remove")
    stop()
    assert(#_G.events == 2)
  ]])
end

T["without mini.notify sends one normal notification instead of command-line updates"] = function()
  child.lua([[
    _G.MiniNotify = nil
    local messages = {}
    vim.notify = function(message) messages[#messages + 1] = message end
    local stop = _G.notifications.running("example")
    assert(vim.deep_equal(messages, { "Running request: example" }))
    assert(#_G.timers == 0)
    stop()
    assert(#messages == 1)
  ]])
end

return T
