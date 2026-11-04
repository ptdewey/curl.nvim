local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([=[
      vim.cmd("syntax enable")
      require("curl")
      source_buf = vim.api.nvim_get_current_buf()
      function render(stdout, stderr, requests, exit_code)
        require("curl.buffers").set_notebook_output(source_buf, { title = "response" }, {
          stdout = stdout, stderr = stderr or "", exit_code = exit_code or 0, elapsed = 0, requests = requests,
        })
        output_buf = require("tests.helpers").output_buf()
        return output_buf
      end
    ]=])
    end,
    post_case = function()
      child.stop()
    end,
  },
})

T["JSON body gets JSON highlighting while metadata and stderr stay separate"] = function()
  child.lua([=[
    local buf = render('{"ok":true}', 'warning: {"not":"a response"}')
    assert(vim.bo[buf].filetype == "json", vim.bo[buf].filetype)
    assert(vim.bo[buf].syntax == "json", vim.bo[buf].syntax)
    vim.api.nvim_buf_call(buf, function()
      assert(vim.fn.synIDattr(vim.fn.synID(1, 1, 1), "name") == "CurlNotebookMetadata")
      local rows = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local body_start
      for index, line in ipairs(rows) do
        if line == "stdout:" then body_start = index + 1; break end
      end
      assert(vim.fn.synIDattr(vim.fn.synID(body_start + 1, 4, 1), "name"):find("json"))
      assert(vim.fn.synIDattr(vim.fn.synID(#rows, 1, 1), "name") == "CurlNotebookStderr")
      assert(table.concat(rows, "\n"):find('warning: {"not":"a response"}', 1, true))
    end)
  ]=])
end

T["URLs and supplied headers replace the directory and stay outside JSON highlighting"] = function()
  child.lua([=[
    local buf = render('{"ok":true}', "", {
      { urls = { "https://example.test/first" }, headers = { "X-First: one", "X-Second: two" } },
      { urls = { "https://example.test/second" }, headers = {} },
    })
    local rows = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(rows, "\n")
    assert(text:find("Request: response\nURL: https://example.test/first\nHeaders:\n  X-First: one\n  X-Second: two\nURL: https://example.test/second", 1, true), text)
    assert(not text:find("Directory:", 1, true), text)
    assert(not text:find("Status:", 1, true), text)
    assert(not text:find("Exit code:", 1, true), text)
    vim.api.nvim_buf_call(buf, function()
      for index, line in ipairs(rows) do
        if line == "stdout:" then
          assert(vim.fn.synIDattr(vim.fn.synID(index + 2, 4, 1), "name"):find("json"))
          break
        end
        if line ~= "" then
          assert(vim.fn.synIDattr(vim.fn.synID(index, 1, 1), "name") == "CurlNotebookMetadata", line)
        end
      end
    end)
  ]=])
end

T["HTTP status is shown only when returned and process failures use an exit code"] = function()
  child.lua([=[
    local function text(body, code)
      local buf = render(body, "", nil, code)
      return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    end
    local plain = text('{"ok":true}')
    assert(not plain:find("Status:", 1, true), plain)
    local http = text('HTTP/1.1 100 Continue\r\n\r\nHTTP/2 201 Created\r\nContent-Type: application/json\r\n\r\n{"ok":true}')
    assert(http:find("Status: 201 Created\n", 1, true), http)
    local failure = text("", 7)
    assert(failure:find("Exit code: 7\n", 1, true), failure)
    assert(not failure:find("Status:", 1, true), failure)
  ]=])
end

T["response windows disable spell checking without changing the source window"] = function()
  child.lua([=[
    vim.wo.spell = true
    local source_win = vim.api.nvim_get_current_win()
    local buf = render('{"ok":true}')
    assert(vim.wo[source_win].spell)
    local output_win = vim.fn.win_findbuf(buf)[1]
    assert(not vim.wo[output_win].spell)
    vim.api.nvim_win_call(output_win, function()
      vim.cmd("split")
      vim.wo.spell = true
    end)
    vim.wo[output_win].spell = true
    render('{"again":true}')
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      assert(not vim.wo[win].spell)
    end
    assert(vim.wo[source_win].spell)
  ]=])
end

T["display normalizes carriage returns and removes terminal escapes from both streams"] = function()
  child.lua([=[
    local buf = render(
      '\27[32mHTTP/1.1 200 OK\27[0m\r\nContent-Type: text/plain\r\n\r\n  response\r\n',
      '\27]0;curl progress\7connecting\r\27[2Kdone\r\n\27]0;finished\27\\warning\n'
    )
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    assert(not text:find("\r", 1, true), vim.inspect(text))
    assert(not text:find("\27", 1, true), vim.inspect(text))
    assert(text:find("HTTP/1.1 200 OK\nContent-Type: text/plain\n\n  response\n", 1, true), text)
    assert(text:find("connecting\ndone\nwarning\n", 1, true), text)
  ]=])
end

T["JSON is formatted after terminal escapes and CRLF are cleaned"] = function()
  child.lua([=[
    local buf = render('\27[32m{"ok":true,"message":"literal \\r\\n"}\27[0m\r\n')
    assert(vim.bo[buf].filetype == "json")
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    assert(text:find('  "ok": true,', 1, true), text)
    assert(text:find('"message": "literal \\r\\n"', 1, true), text)
    assert(not text:find("\r", 1, true), vim.inspect(text))
    assert(not text:find("\27", 1, true), vim.inspect(text))
  ]=])
end

T["reused output switches between JSON and text without stale syntax"] = function()
  child.lua([=[
    for _, body in ipairs({ '{"ok":true}', '[1,2]', 'null', 'false', '42', '"hello"' }) do
      local buf = render(body)
      assert(vim.bo[buf].filetype == "json", body)
      render("not JSON\nsecond line")
      assert(vim.bo[buf].filetype == "text")
      assert(vim.bo[buf].syntax ~= "json")
      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      assert(text:find("not JSON\nsecond line", 1, true))
      render("")
      assert(vim.bo[buf].filetype == "text")
    end
  ]=])
end

T["closing shared output wipes it and the next request recreates it"] = function()
  child.lua([=[
    local buf = render('{"first":true}')
    vim.api.nvim_win_close(vim.fn.win_findbuf(buf)[1], true)
    assert(not vim.api.nvim_buf_is_valid(buf))
    assert(vim.api.nvim_buf_is_valid(source_buf))
    local second = render('{"second":true}')
    assert(second ~= buf)
    assert(render('{"updated":true}') == second)
    assert(#vim.fn.win_findbuf(second) == 1)
    vim.api.nvim_buf_delete(second, { force = true })
    local replacement = render('{"third":true}')
    assert(replacement ~= buf)
    assert(vim.api.nvim_buf_is_valid(replacement))
    assert(#vim.fn.win_findbuf(replacement) == 1)
    local text = table.concat(vim.api.nvim_buf_get_lines(replacement, 0, -1, false), "\n")
    assert(text:find('"third": true', 1, true), text)
  ]=])
end

T["response buffers are unlisted scratch buffers without swap files"] = function()
  child.lua([=[
    local buf = render("temporary")
    assert(vim.api.nvim_buf_get_name(buf) == "")
    assert(vim.bo[buf].buftype == "nofile")
    assert(vim.bo[buf].bufhidden == "wipe")
    assert(not vim.bo[buf].buflisted)
    assert(not vim.bo[buf].swapfile)
  ]=])
end

T["session snapshots discard output splits but preserve unsaved source"] = function()
  child.lua([=[
    if vim.fn.exists("##SessionWritePre") == 0 then return end
    local source_win = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_name(source_buf, vim.fn.tempname() .. ".sh")
    vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "unsaved source" })
    local sessionoptions = vim.o.sessionoptions
    local buf = render("temporary")
    vim.api.nvim_win_call(vim.fn.win_findbuf(buf)[1], function()
      vim.cmd("split")
    end)
    local session = vim.fn.tempname()
    vim.cmd.mksession({ session, bang = true })
    local text = table.concat(vim.fn.readfile(session), "\n")
    vim.fn.delete(session)
    assert(not text:find("Curl", 1, true), text)
    assert(not vim.api.nvim_buf_is_valid(buf))
    assert(#vim.api.nvim_list_wins() == 1)
    assert(vim.api.nvim_get_current_win() == source_win)
    assert(vim.api.nvim_get_current_buf() == source_buf)
    assert(vim.bo[source_buf].modified)
    assert(vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)[1] == "unsaved source")
    assert(vim.o.sessionoptions == sessionoptions)
    assert(vim.api.nvim_buf_is_valid(render("fresh")))
  ]=])
end

T["session snapshots also discard output when it is the last window"] = function()
  child.lua([=[
    if vim.fn.exists("##SessionWritePre") == 0 then return end
    local source_win = vim.api.nvim_get_current_win()
    local buf = render("temporary")
    vim.api.nvim_win_close(source_win, true)
    local session = vim.fn.tempname()
    vim.cmd.mksession({ session, bang = true })
    local text = table.concat(vim.fn.readfile(session), "\n")
    vim.fn.delete(session)
    assert(not text:find("Curl", 1, true), text)
    assert(not vim.api.nvim_buf_is_valid(buf))
    assert(vim.api.nvim_buf_is_valid(source_buf))
    assert(#vim.api.nvim_list_wins() == 1)
  ]=])
end

return T
