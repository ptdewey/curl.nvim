local new_set = MiniTest.new_set
local runner = require("curl.notebook_runner")
local T = new_set()

local function run(options)
  local result
  local done = false
  local handle, err = runner.start(options, function(value)
    result = value
    done = true
  end)
  assert(handle, err)
  vim.wait(5000, function()
    return done
  end, 10)
  assert(done, "runner did not complete")
  return result
end

local function options(setup, body, extra)
  local value = {
    setup = setup,
    body = body,
    script = setup .. "\n" .. body,
    cwd = vim.fn.getcwd(),
  }
  for key, item in pairs(extra or {}) do
    value[key] = item
  end
  return value
end

T["runs setup and body in an isolated shell"] = function()
  local first = run(options("VALUE=from_setup", "printf '%s\n' \"$VALUE\"; VALUE=changed"))
  local second = run(options("", "printf '%s\n' \"${VALUE-unset}\""))
  MiniTest.expect.equality("from_setup\n", first.stdout)
  MiniTest.expect.equality("unset\n", second.stdout)
end

T["setup failure prevents body without errexit"] = function()
  local result = run(options("(exit 7)", "printf ran"))
  MiniTest.expect.equality("", result.stdout)
  MiniTest.expect.equality(7, result.exit_code)
end

T["captures multiline streams and does not block"] = function()
  local result
  local done = false
  runner.start(options("", "printf 'a\nb\n'; printf 'x\ny\n' >&2; sleep 0.1"), function(value)
    result, done = value, true
  end)
  MiniTest.expect.equality(false, done)
  vim.wait(5000, function()
    return done
  end, 10)
  MiniTest.expect.equality("a\nb\n", result.stdout)
  MiniTest.expect.equality("x\ny\n", result.stderr)
end

T["does not execute inherited BASH_ENV"] = function()
  local path = vim.fn.tempname()
  local envfile = path .. ".env"
  vim.fn.writefile({ "touch " .. vim.fn.shellescape(path) }, envfile)
  local previous = vim.env.BASH_ENV
  vim.env.BASH_ENV = envfile
  local ok, result = pcall(run, options("", "printf ok"))
  vim.env.BASH_ENV = previous
  assert(ok, result)
  MiniTest.expect.equality("ok", result.stdout)
  MiniTest.expect.equality(0, vim.fn.filereadable(path))
  vim.fn.delete(envfile)
end

T["temporary scripts are private and cleaned on exit"] = function()
  local original = vim.fn.tempname
  local path
  vim.fn.tempname = function()
    path = original()
    return path
  end
  local result
  local done = false
  runner.start(options("", "sleep 0.1"), function(value)
    result, done = value, true
  end)
  vim.fn.tempname = original
  MiniTest.expect.equality(384, vim.uv.fs_stat(path).mode % 512)
  vim.wait(5000, function()
    return done
  end, 10)
  MiniTest.expect.equality(nil, vim.uv.fs_stat(path))
  path = nil
  vim.fn.tempname = function()
    path = original()
    return path
  end
  local failed = run(options("(exit 3)", "true"))
  vim.fn.tempname = original
  MiniTest.expect.equality(3, failed.exit_code)
  MiniTest.expect.equality(nil, vim.uv.fs_stat(path))
end

T["preserves a notebook status variable"] = function()
  local result = run(options("status=kept", 'printf %s "$status"'))
  MiniTest.expect.equality("kept", result.stdout)
end

T["runs a body larger than argv limits"] = function()
  local body = "printf %s " .. string.rep("x", 160000)
  local result = run(options("", body))
  MiniTest.expect.equality(160000, #result.stdout)
end

T["reports a missing shell"] = function()
  local handle, err = runner.start(options("", "true", { shell = { "/missing/not-a-shell" } }), function() end)
  MiniTest.expect.equality(nil, handle)
  MiniTest.expect.equality(true, type(err) == "string" and err:find("failed to start shell", 1, true) ~= nil)
end

T["cancels a running process"] = function()
  local result
  local marker = vim.fn.tempname()
  local original = vim.fn.tempname
  local script_path
  vim.fn.tempname = function()
    script_path = original()
    return script_path
  end
  local handle = runner.start(
    options("", "((sleep 0.3; touch " .. vim.fn.shellescape(marker) .. ") & wait) & wait"),
    function(value)
      result = value
    end
  )
  vim.fn.tempname = original
  MiniTest.expect.equality(384, vim.uv.fs_stat(script_path).mode % 512)
  vim.wait(100, function()
    return false
  end, 10)
  handle.cancel()
  vim.wait(5000, function()
    return result ~= nil
  end, 10)
  vim.wait(400, function()
    return vim.fn.filereadable(marker) == 1
  end, 10)
  MiniTest.expect.equality(true, result.cancelled)
  MiniTest.expect.equality(0, vim.fn.filereadable(marker))
  MiniTest.expect.equality(nil, vim.uv.fs_stat(script_path))
end

return T
