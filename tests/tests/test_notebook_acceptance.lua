local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([=[
      require("curl")
      function source(lines, cursor)
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.api.nvim_win_set_cursor(0, { cursor or #lines, 0 })
        return buf
      end
      function result(buf)
        local output = vim.fn.bufnr("Curl notebook output " .. buf)
        return output ~= -1 and table.concat(vim.api.nvim_buf_get_lines(output, 0, -1, false), "\n") or nil
      end
      function execute(buf)
        local before = result(buf)
        require("curl").run()
        assert(vim.wait(5000, function() return result(buf) and result(buf) ~= before end, 10), "no new result")
        return result(buf)
      end
    ]=])
    end,
    post_case = function()
      child.stop()
    end,
  },
})

T["unsaved environment selection and local assignments stay isolated on success and failure"] = function()
  child.lua([=[
    local env = vim.fn.environ()
    local buf = source({
      "ENV=local", "VALUE=shared", "### first", "OTHER=wrong; printf wrong",
      "### middle", "VALUE=local_override", [[printf '%s:%s:%s\n' "$ENV" "$VALUE" "${OTHER-unset}"]],
      "### last", "printf wrong",
    }, 5)
    local out = execute(buf)
    assert(out:find("local:local_override:unset", 1, true), out)
    assert(not out:find("wrong", 1, true), out)
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "ENV=dev" })
    vim.api.nvim_win_set_cursor(0, { 7, 0 })
    out = execute(buf)
    assert(out:find("dev:local_override:unset", 1, true), out)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "NOTEBOOK_TEST_TOKEN=failed", [[printf 'before\nfailure\n']], [[printf 'setup\nerror\n' >&2]], "(exit 7)",
      "### stopped", "printf MUST_NOT_RUN",
    })
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    out = execute(buf)
    assert(out:find("Status: 7", 1, true), out)
    assert(out:find("before\nfailure\n", 1, true), out)
    assert(out:find("setup\nerror\n", 1, true), out)
    assert(not out:find("MUST_NOT_RUN", 1, true), out)
    assert(vim.deep_equal(env, vim.fn.environ()), "editor environment changed")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "### fresh", [[printf '%s' "${NOTEBOOK_TEST_TOKEN-unset}"]] })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    out = execute(buf)
    assert(out:find("stdout:\nunset", 1, true), out)
  ]=])
end

T["overlap rejected and separate sources retain their own results after cancellation"] = function()
  child.lua([=[
    local errors = {}
    require("curl.notifications").error = function(message) errors[#errors + 1] = message end
    local first = source({ "### slow", "printf started; sleep 3; printf finished" })
    require("curl").run()
    require("curl").run()
    assert(#errors == 1 and errors[1]:find("already running"), vim.inspect(errors))
    local second = source({ "### other", "printf independent" })
    local out = execute(second)
    assert(out:find("independent", 1, true), out)
    require("curl").cancel(first)
    assert(vim.wait(5000, function() return result(first) ~= nil end, 10))
    assert(result(first):find("Status: cancelled", 1, true), result(first))
    assert(not result(first):find("finished", 1, true), result(first))
    assert(result(second) == out, "another source result overwritten")
  ]=])
end

T["opening editing saving and invalid selections never launch shell"] = function()
  child.lua([=[
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local path = root .. "/requests.curl"
    vim.fn.writefile({ "VALUE=setup", "### empty", "# nothing" }, path)
    local starts = 0
    require("curl.notebook_runner").start = function() starts = starts + 1; error("unexpected launch") end
    require("curl.notifications").error = function() end
    vim.cmd.edit(vim.fn.fnameescape(path))
    vim.api.nvim_buf_set_lines(0, 2, -1, false, { "# edited" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    vim.api.nvim_exec_autocmds("InsertLeave", { buffer = 0 })
    assert(vim.bo.modified, "editing unexpectedly saved the notebook")
    vim.cmd.write()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    require("curl").run()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    require("curl").run()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "printf no_markers" })
    require("curl").run()
    assert(starts == 0, "implicit or invalid selection launched shell")
    vim.fn.delete(root, "rf")
  ]=])
end

T["relative input files resolve from an unsaved named source directory"] = function()
  child.lua([=[
    local root = vim.fn.tempname() .. " directory with spaces"
    vim.fn.mkdir(root, "p")
    vim.fn.writefile({ "relative body" }, root .. "/body.txt")
    local buf = source({ "### relative", "cat body.txt; pwd" })
    vim.api.nvim_buf_set_name(buf, root .. "/unsaved.curl")
    local out = execute(buf)
    assert(out:find("relative body\n" .. root, 1, true), out)
    assert(vim.fn.filereadable(root .. "/unsaved.curl") == 0, "source autosaved")
    vim.fn.delete(root, "rf")
  ]=])
end

return T
