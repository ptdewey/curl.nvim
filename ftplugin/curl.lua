vim.bo.syntax = "sh"
vim.bo.commentstring = "# %s"

local config = require("curl.config")
local execute_mapping = config.get("mappings")["execute_curl"]
vim.api.nvim_buf_set_keymap(
	0,
	"n",
	execute_mapping,
	"<cmd>lua require('curl.api').execute_curl()<CR>",
	{ noremap = true, silent = true, desc = "Execute Curl" }
)

vim.treesitter.language.register("bash", "curl")
local parser_ok, parser = pcall(vim.treesitter.get_parser, 0, "bash")
if parser_ok and parser then
	pcall(require("curl.treesitter").add_treesitter_highlighting)
	return
end
