local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([=[
      vim.cmd("syntax enable")
      require("curl")
      source_buf = vim.api.nvim_get_current_buf()
      function render(stdout, stderr)
        require("curl.buffers").set_notebook_output(source_buf, { title = "response" }, "/tmp", {
          stdout = stdout, stderr = stderr or "", exit_code = 0, elapsed = 0,
        })
        output_buf = vim.fn.bufnr("Curl notebook output")
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
      assert(vim.fn.synIDattr(vim.fn.synID(8, 4, 1), "name"):find("json"))
      local rows = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert(vim.fn.synIDattr(vim.fn.synID(#rows, 1, 1), "name") == "CurlNotebookStderr")
      assert(table.concat(rows, "\n"):find('warning: {"not":"a response"}', 1, true))
    end)
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

T["closed shared output is reopened and wiped output is recreated"] = function()
  child.lua([=[
    local buf = render('{"first":true}')
    vim.api.nvim_win_close(vim.fn.win_findbuf(buf)[1], true)
    assert(vim.api.nvim_buf_is_valid(buf))
    vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
    source_buf = vim.api.nvim_get_current_buf()
    assert(render('{"second":true}') == buf)
    assert(#vim.fn.win_findbuf(buf) == 1)
    vim.api.nvim_buf_delete(buf, { force = true })
    local replacement = render('{"third":true}')
    assert(replacement ~= buf)
    assert(vim.api.nvim_buf_is_valid(replacement))
    assert(#vim.fn.win_findbuf(replacement) == 1)
    local text = table.concat(vim.api.nvim_buf_get_lines(replacement, 0, -1, false), "\n")
    assert(text:find('"third": true', 1, true), text)
  ]=])
end

return T
