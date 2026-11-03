local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([=[
      vim.cmd("syntax enable")
      require("curl").setup({ notebook_mode = true })
      source_buf = vim.api.nvim_get_current_buf()
      function render(stdout, stderr)
        require("curl.buffers").set_notebook_output(source_buf, { title = "response" }, "/tmp", {
          stdout = stdout, stderr = stderr or "", exit_code = 0, elapsed = 0,
        })
        output_buf = vim.fn.bufnr("Curl notebook output " .. source_buf)
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

return T
