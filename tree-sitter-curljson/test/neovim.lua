local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")

local function read(path)
  return table.concat(vim.fn.readfile(path), "\n")
end

local function compile(name, source)
  local output = temp .. "/" .. name .. ".so"
  local shared = vim.uv.os_uname().sysname == "Darwin" and "-dynamiclib" or "-shared"
  local result = vim
    .system({
      vim.env.CC or "cc",
      shared,
      "-fPIC",
      "-I" .. source,
      source .. "/parser.c",
      "-o",
      output,
    }, { text = true })
    :wait()
  assert(result.code == 0, result.stderr)
  vim.treesitter.language.add(name, { path = output })
end

local function test()
  compile("curljson", "src")
  compile("json", "node_modules/tree-sitter-json/src")
  vim.treesitter.query.set("curljson", "injections", read("queries/injections.scm"))
  local highlight_source = read("queries/highlights.scm")
  local highlights = vim.treesitter.query.parse("curljson", highlight_source)
  vim.treesitter.query.set("curljson", "highlights", highlight_source)
  vim.treesitter.query.set("json", "highlights", read("node_modules/tree-sitter-json/queries/highlights.scm"))
  local header = table.concat({
    "Request: POST literal multiline JSON",
    "Directory: /tmp/project with spaces/日本語",
    "Status: 0",
    "Elapsed: 0.139s",
    "",
    "stdout:",
    "",
  }, "\n")
  local count = 0

  local function check(body, stderr, injected, json_error, crlf)
    local text = header .. body
    if stderr then
      text = text .. "\n\nstderr:\n" .. stderr
    end
    if crlf then
      text = text:gsub("\n", "\r\n")
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
    local parser = vim.treesitter.get_parser(buf, "curljson")
    local root = parser:parse(true)[1]:root()
    assert(not root:has_error(), root:sexpr())
    local json_parser = parser:children().json
    assert((json_parser ~= nil) == injected, "unexpected injection for " .. vim.inspect(body))
    if json_parser then
      local json_root = json_parser:trees()[1]:root()
      assert(json_root:has_error() == (json_error or false), json_root:sexpr())
      local row = json_root:range()
      assert(row >= 6, "JSON injection includes metadata")
      local content = vim.treesitter.get_node_text(json_root, buf)
      assert(not content:find("\nstderr:\n", 1, true), "JSON injection includes stderr")
    end
    local captures = {}
    for id, node in highlights:iter_captures(root, buf) do
      local capture = highlights.captures[id]
      captures[capture] = captures[capture] or {}
      table.insert(captures[capture], vim.treesitter.get_node_text(node, buf))
    end
    assert(captures.property[1] == "Request:")
    assert(captures["string.special.path"][1]:find("project with spaces", 1, true))
    if stderr then
      assert(captures.comment[1]:find("warning", 1, true))
    end
    vim.api.nvim_buf_delete(buf, { force = true })
    count = count + 1
  end

  check('{\n  "ok": true, "data": [1, null]\n}', "warning: {not JSON}\nstderr:\nstill a warning", true)
  for _, body in ipairs({ "[]", "{}", "true", "false", "null", "42", "-1.25e2", '"a string"', "  \n[1,2]" }) do
    check(body, nil, true)
  end
  check("plain text\nRequest: body text\nStatus: not metadata\nstdout:\nstderr: not a delimiter", nil, false)
  check("", nil, false)
  check("progress 10%\rprogress 100%", nil, false)
  check("false alarm", nil, false)
  check("nullified", nil, false)
  check("<html><body>Not JSON</body></html>", nil, false)
  check('{"stderr:": "inside JSON", "Request:": "also inside JSON"}', nil, true)
  check("", "warning: no stdout", false)
  check('{"incomplete":', "warning: incomplete JSON", true, true)
  check('{"ok":true}', "warning: CRLF", true, false, true)

  local malformed = vim.api.nvim_create_buf(false, true)
  local bad_header = header:gsub("Status: 0", "Status: unknown")
  vim.api.nvim_buf_set_lines(malformed, 0, -1, false, vim.split(bad_header, "\n"))
  assert(vim.treesitter.get_parser(malformed, "curljson"):parse(true)[1]:root():has_error())
  vim.api.nvim_buf_delete(malformed, { force = true })
  count = count + 1

  local incremental = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(incremental, 0, -1, false, vim.split(header .. '{"ok":true}', "\n"))
  local parser = vim.treesitter.get_parser(incremental, "curljson")
  parser:parse(true)
  assert(parser:children().json)
  vim.api.nvim_buf_set_lines(incremental, 6, -1, false, { "plain text" })
  parser:parse(true)
  local json_parser = parser:children().json
  assert(not json_parser or #json_parser:trees() == 0, "stale JSON injection after edit")
  vim.api.nvim_buf_delete(incremental, { force = true })
  count = count + 1

  vim.opt.runtimepath:append(vim.fn.fnamemodify("..", ":p"))
  local source = vim.api.nvim_get_current_buf()
  require("curl.buffers").set_notebook_output(source, { title = "real renderer" }, "/tmp/path with spaces", {
    stdout = '{"ok":true}',
    stderr = "warning from shell",
    exit_code = 7,
    elapsed = 0.139,
  })
  local output = vim.fn.bufnr("Curl notebook output " .. source)
  local rendered = vim.treesitter.get_parser(output, "curljson")
  local root = rendered:parse(true)[1]:root()
  assert(not root:has_error(), root:sexpr())
  assert(rendered:children().json, "real plugin output did not inject JSON")
  vim.treesitter.start(output, "curljson")
  vim.cmd("redraw")
  local metadata_captures = vim.treesitter.get_captures_at_pos(output, 0, 0)
  assert(
    vim.iter(metadata_captures):any(function(capture)
      return capture.lang == "curljson" and capture.capture == "property"
    end),
    vim.inspect(metadata_captures)
  )
  local body_captures = vim.treesitter.get_captures_at_pos(output, 7, 3)
  assert(
    vim.iter(body_captures):any(function(capture)
      return capture.lang == "json" and capture.capture:find("string")
    end),
    vim.inspect(body_captures)
  )
  vim.treesitter.stop(output)
  count = count + 1

  local setup = assert(read("README.md"):match("```lua\n(.-)\n```"))
  setup = setup:gsub("local root = vim.fn.expand%b()", function()
    return "local root = " .. string.format("%q", vim.fn.getcwd())
  end)
  setup = setup:gsub(vim.pesc('root .. "/parser/curljson.so"'), function()
    return string.format("%q", temp .. "/curljson.so")
  end)
  assert(loadstring(setup))()
  require("curl.buffers").set_notebook_output(source, { title = "automatic attachment" }, "/tmp", {
    stdout = '{"automatic":true}',
    stderr = "",
    exit_code = 0,
    elapsed = 0.1,
  })
  assert(
    vim.wait(1000, function()
      return vim.treesitter.highlighter.active[output] ~= nil
    end, 10),
    "README setup did not attach the wrapper highlighter"
  )
  assert(vim.treesitter.highlighter.active[output].tree:lang() == "curljson")
  vim.treesitter.stop(output)
  count = count + 1

  print(string.format("Passed %d Neovim parser/injection checks", count))
end

local ok, err = xpcall(test, debug.traceback)
vim.fn.delete(temp, "rf")
if not ok then
  error(err)
end
