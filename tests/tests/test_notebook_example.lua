local T = MiniTest.new_set()
local notebook = require("curl.notebook")
local runner = require("curl.notebook_runner")

T["documented notebook reaches fake curl unchanged"] = function()
  local root = vim.fn.tempname() .. " notebook example"
  vim.fn.mkdir(root, "p")
  local fake = root .. "/curl"
  vim.fn.writefile({
    "#!" .. vim.fn.exepath("bash"),
    [[printf '%s\n' "$@"]],
    "cat",
  }, fake)
  vim.uv.fs_chmod(fake, 448)
  local lines = vim.fn.readfile("examples/requests.curl")
  table.insert(lines, 1, "PATH=" .. vim.fn.shellescape(root) .. ":$PATH")
  local selected = assert(notebook.extract(lines, #lines))
  local result
  local ok, err = pcall(function()
    local handle, start_error = runner.start({
      setup = selected.setup,
      body = selected.body,
      script = selected.script,
      cwd = root,
    }, function(value)
      result = value
    end)
    assert(handle, start_error)
    assert(
      vim.wait(5000, function()
        return result ~= nil
      end, 10),
      "example did not finish"
    )
    assert(result.exit_code == 0, result.stderr)
    MiniTest.expect.equality(result.stderr, "")
    MiniTest.expect.equality(
      result.stdout,
      table.concat({
        "--silent",
        "--show-error",
        "--request",
        "PATCH",
        "http://localhost:8099/api/v1/applications/48047",
        "--header",
        "Content-Type: application/json",
        "--data",
        "@-",
        "{",
        '  "applicationId": "48047",',
        '  "name": "Customer\'s application"',
        "}",
        "",
      }, "\n")
    )
  end)
  vim.fn.delete(root, "rf")
  if not ok then
    error(err)
  end
end

return T
