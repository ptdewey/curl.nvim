local M = {}

M.output_buf = function()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "nofile" then
      local first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
      if first:match("^Request: ") then
        return buf
      end
    end
  end
  return -1
end

return M
