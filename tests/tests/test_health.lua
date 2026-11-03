local T = MiniTest.new_set()

local function check_health(shell, available)
  local config = require("curl.config")
  config.setup({ shell = { shell } })
  local events, probes = {}, {}
  local old = {
    start = vim.health.start,
    ok = vim.health.ok,
    warn = vim.health.warn,
    error = vim.health.error,
    executable = vim.fn.executable,
  }
  vim.health.start = function(message)
    events[#events + 1] = { "start", message }
  end
  vim.health.ok = function(message)
    events[#events + 1] = { "ok", message }
  end
  vim.health.warn = function(message)
    events[#events + 1] = { "warn", message }
  end
  vim.health.error = function(message)
    events[#events + 1] = { "error", message }
  end
  vim.fn.executable = function(name)
    probes[#probes + 1] = name
    return available[name] and 1 or 0
  end
  local ok, err = xpcall(function()
    require("curl.health").check()
  end, debug.traceback)
  vim.health.start, vim.health.ok, vim.health.warn, vim.health.error = old.start, old.ok, old.warn, old.error
  vim.fn.executable = old.executable
  config.setup()
  assert(ok, err)
  return events, probes
end

T["health checks selected shell and curl but never jq"] = function()
  local events, probes = check_health("custom-shell", { ["custom-shell"] = true })
  MiniTest.expect.equality({ "custom-shell", "curl" }, probes)
  MiniTest.expect.equality({
    { "start", "Notebook execution" },
    { "ok", "Configured shell available: custom-shell" },
    { "warn", "curl not found on the editor's PATH; provide it in notebook setup if requests use it" },
  }, events)
end

T["health reports missing configured shell as an error"] = function()
  local events, probes = check_health("missing-shell", { curl = true })
  MiniTest.expect.equality({ "missing-shell", "curl" }, probes)
  MiniTest.expect.equality({
    { "start", "Notebook execution" },
    { "error", "Configured shell not found: missing-shell" },
    { "ok", "curl available on the editor's PATH" },
  }, events)
end

return T
