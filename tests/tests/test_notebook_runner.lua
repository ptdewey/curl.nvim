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

T["curl defaults apply to setup and body without changing arguments or PATH selection"] = function()
  local dir = vim.fn.tempname() .. " curl tools"
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/curl"
  vim.fn.writefile({ "#!/bin/sh", "printf '<%s>\\n' \"$@\"" }, path)
  vim.fn.setfperm(path, "rwx------")
  local result = run(options(
    "export PATH=" .. vim.fn.shellescape(dir) .. ':"$PATH"\ncurl "setup url"',
    [[curl --no-silent --no-show-error 'body url' --data '{"name": "a b"}'; command curl bypass]]
  ))
  vim.fn.delete(dir, "rf")
  MiniTest.expect.equality(0, result.exit_code)
  MiniTest.expect.equality(
    table.concat({
      "<--silent>",
      "<--show-error>",
      "<setup url>",
      "<--silent>",
      "<--show-error>",
      "<--no-silent>",
      "<--no-show-error>",
      "<body url>",
      "<--data>",
      '<{"name": "a b"}>',
      "<bypass>",
      "",
    }, "\n"),
    result.stdout
  )
end

T["curl hides progress by default but retains transport errors and exit status"] = function()
  local path = vim.fn.tempname()
  vim.fn.writefile({ "response body" }, path)
  local url = vim.fn.shellescape("file://" .. path)
  local success = run(options("", "curl " .. url))
  local progress = run(options("", "curl --no-silent " .. url, { shell = { "/bin/sh" } }))
  vim.fn.delete(path)
  local failure = run(options("", "curl " .. url))
  local quiet_failure = run(options("", "curl --no-show-error " .. url))
  MiniTest.expect.equality("response body\n", success.stdout)
  MiniTest.expect.equality("", success.stderr)
  MiniTest.expect.equality(0, success.exit_code)
  MiniTest.expect.equality(success.stdout, progress.stdout)
  MiniTest.expect.equality(0, progress.exit_code)
  MiniTest.expect.equality(true, progress.stderr:find("% Total", 1, true) ~= nil)
  MiniTest.expect.equality("", failure.stdout)
  MiniTest.expect.equality(true, failure.stderr:find("curl:", 1, true) ~= nil)
  MiniTest.expect.equality(true, failure.exit_code ~= 0)
  MiniTest.expect.equality(nil, failure.stderr:find("% Total", 1, true))
  MiniTest.expect.equality("", quiet_failure.stderr)
  MiniTest.expect.equality(failure.exit_code, quiet_failure.exit_code)
end

T["captures expanded request URLs and headers separately from both streams"] = function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile({ "#!/bin/sh", "printf body; printf warning >&2; exit 7" }, dir .. "/curl")
  vim.fn.setfperm(dir .. "/curl", "rwx------")
  local result = run(options(
    "PATH=" .. vim.fn.shellescape(dir) .. ':"$PATH"\nBASE_URL=https://example.test\nTOKEN="a b"',
    [[curl --request POST "$BASE_URL/first" -H "Authorization: Bearer $TOKEN" --data-raw 'https://not-a-url'
curl --url="$BASE_URL/second" --header='X-Test: two' --header='X-Empty:'
command curl https://bypassed.test]]
  ))
  vim.fn.delete(dir, "rf")
  MiniTest.expect.equality({
    { urls = { "https://example.test/first" }, headers = { "Authorization: Bearer a b" } },
    { urls = { "https://example.test/second" }, headers = { "X-Test: two", "X-Empty:" } },
  }, result.requests)
  MiniTest.expect.equality("bodybodybody", result.stdout)
  MiniTest.expect.equality("warningwarningwarning", result.stderr)
  MiniTest.expect.equality(7, result.exit_code)
end

T["request metadata is private and cleaned on success failure and launch failure"] = function()
  for _, scenario in ipairs({
    { setup = "", body = "sleep 0.1" },
    { setup = "(exit 7)", body = "true" },
    { setup = "", body = "true", shell = { "/missing/not-a-shell" } },
  }) do
    local paths = {}
    local original = vim.fn.tempname
    vim.fn.tempname = function()
      local path = original()
      paths[#paths + 1] = path
      return path
    end
    local result
    local handle, err = runner.start(options(scenario.setup, scenario.body, { shell = scenario.shell }), function(value)
      result = value
    end)
    vim.fn.tempname = original
    MiniTest.expect.equality(2, #paths)
    if handle then
      for _, path in ipairs(paths) do
        MiniTest.expect.equality(384, vim.uv.fs_stat(path).mode % 512)
      end
      assert(vim.wait(5000, function() return result ~= nil end, 10))
    else
      assert(err:find("failed to start shell", 1, true), err)
    end
    for _, path in ipairs(paths) do
      MiniTest.expect.equality(nil, vim.uv.fs_stat(path))
    end
  end
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
  local paths = {}
  vim.fn.tempname = function()
    script_path = original()
    paths[#paths + 1] = script_path
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
  for _, path in ipairs(paths) do
    MiniTest.expect.equality(nil, vim.uv.fs_stat(path))
  end
end

return T
