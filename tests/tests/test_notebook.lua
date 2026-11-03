local new_set = MiniTest.new_set
local notebook = require("curl.notebook")
local T = new_set()

T["extracts setup and selected block without rewriting source"] = function()
  local lines = {
    "ENV=local",
    "# shared setup",
    "### First request",
    "curl first",
    "### Middle request",
    "ID=42",
    "curl --data '{",
    [=[  "name": "it's fine" ]=],
    "}' " .. string.char(92),
    "  --header X: y",
    "",
    "### Last request",
    "curl last",
  }
  local result = notebook.extract(lines, 10)
  MiniTest.expect.equality(result.setup, table.concat({ "ENV=local", "# shared setup" }, "\n"))
  MiniTest.expect.equality(
    result.body,
    table.concat(
      { "ID=42", "curl --data '{", [=[  "name": "it's fine" ]=], "}' " .. string.char(92), "  --header X: y", "" },
      "\n"
    )
  )
  MiniTest.expect.equality(result.title, "Middle request")
  MiniTest.expect.equality(result.marker_line, 5)
  MiniTest.expect.equality(result.end_line, 11)
  MiniTest.expect.equality(result.script, result.setup .. "\n" .. result.body)
  for cursor_line = 5, 11 do
    MiniTest.expect.equality(notebook.extract(lines, cursor_line).body, result.body)
  end
end

T["marker line selects its introduced block and accepts end of line marker"] = function()
  local result = notebook.extract({ "### One", "echo one", "###", "echo two" }, 3)
  MiniTest.expect.equality(result.title, "")
  MiniTest.expect.equality(result.marker_line, 3)
  MiniTest.expect.equality(result.body, "echo two")
end

T["recognizes only column-one delimiters"] = function()
  local lines = { "### One", "echo ### inline", "#### not a marker", " ### not a marker", "echo done" }
  local result = notebook.extract(lines, 5)
  MiniTest.expect.equality(result.body, table.concat({ lines[2], lines[3], lines[4], lines[5] }, "\n"))
  MiniTest.expect.equality(result.end_line, 5)
end

T["reserves marker lines even inside heredocs"] = function()
  local result = notebook.extract({ "### One", "cat <<EOF", "### Two", "echo next" }, 2)
  MiniTest.expect.equality(result.body, "cat <<EOF")
  MiniTest.expect.equality(result.end_line, 2)
end

T["rejects missing markers and cursor positions in shared setup"] = function()
  local result, err = notebook.extract({ "ENV=local", "echo setup" }, 1)
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(err, "no request markers found")
  result, err = notebook.extract({ "ENV=local", "### Request", "echo body" }, 1)
  MiniTest.expect.equality(result, nil)
  MiniTest.expect.equality(err, "cursor is in shared setup")
end

T["rejects blocks containing only whitespace and comments"] = function()
  for _, body in ipairs({ { "", "  " }, { "# note", "  # another note" } }) do
    local lines = { "### Empty" }
    vim.list_extend(lines, body)
    local result, err = notebook.extract(lines, 1)
    MiniTest.expect.equality(result, nil)
    MiniTest.expect.equality(err, "request block is empty")
  end
end

T["treats assignments as executable content and handles final block without newline"] = function()
  local result = notebook.extract({ "### Request", "  # note", "ID=42" }, 3)
  MiniTest.expect.equality(result.body, table.concat({ "  # note", "ID=42" }, "\n"))
  MiniTest.expect.equality(result.end_line, 3)
end

T["preserves setup and body line boundaries including whitespace"] = function()
  local result = notebook.extract({ "", "ENV=local", "", "### Run", "", "curl x", "" }, 6)
  MiniTest.expect.equality(result.setup, table.concat({ "", "ENV=local", "" }, "\n"))
  MiniTest.expect.equality(result.body, table.concat({ "", "curl x", "" }, "\n"))
end

return T
