# tree-sitter-curljson

A small Tree-sitter grammar for curl.nvim's mixed response buffer. It parses the
metadata and stream boundaries, then injects the existing JSON parser into
JSON-looking stdout. It does not implement JSON parsing itself.

This directory is a standalone parser project. curl.nvim does not install or
activate it automatically; its existing highlighting remains the default.

## Format

```text
Request: POST literal multiline JSON
Directory: /home/patrick/project with spaces
Status: 0
Elapsed: 0.139s

stdout:
{
  "message": "Hello from curl.nvim"
}

stderr:
warning: example diagnostic
```

The four metadata fields appear once, in that order. `Status:` holds an integer
process exit code or `cancelled`, not an HTTP status. `Elapsed:` is a decimal
number of seconds followed by `s`, matching the plugin's renderer.

`stdout:` introduces the response body. `stderr:` is optional and runs to EOF.
Both bodies may be empty. LF and CRLF line endings, paths with spaces, Unicode,
and a final body line without a newline are supported. Carriage returns within
process output remain part of the body.

Named nodes include `request`, `directory`, `status`, `elapsed`, `stdout`, and
`stderr`. Fields expose the request `title`, directory `path`, status `value`,
elapsed `duration`, and each stream's `body`. See `src/node-types.json` for the
full tree shape and `test/corpus/responses.txt` for examples.

### Boundary restriction

A column-one `stderr:` line followed by a newline is reserved after `stdout:`.
If arbitrary stdout contains that exact line, the parser interprets it as the
start of stderr. It cannot distinguish identical text from an actual section
boundary without a different display format or out-of-band source ranges.

`stderr: extra text`, indented markers, and metadata-looking lines within stdout
are ordinary body text. JSON keys and string values containing `stderr:` are
also ordinary JSON; valid JSON strings cannot contain unescaped newlines.
Once stderr begins, further `stderr:` lines belong to stderr.

This describes the current generated display, not a lossless serialization of
two process streams. Do not use it to recover authoritative process output.

## JSON injection and highlighting

`queries/highlights.scm` highlights metadata names, request titles, paths, exit
codes, durations, stream labels, and stderr. `queries/injections.scm` injects
`json` into stdout whose first non-whitespace character looks like a JSON object,
array, string, or number, or whose entire trimmed value is `true`, `false`, or
`null`. Ordinary text and empty output are not injected. Metadata and stderr
never enter the JSON tree.

This is a lexical check, not JSON validation. Truncated JSON and JSON-looking
text can still receive an injected tree with error nodes. The wrapper continues
to parse the metadata and streams, and preserves the body. An installed JSON
parser and its highlight queries provide the JSON colors; this project supplies
only the wrapper and injection queries.

## Generate and test

Requirements: Node.js/npm, a C compiler, and the Tree-sitter CLI on `PATH`.
The Neovim integration checks also require Neovim with Tree-sitter support.
The CLI used during development was 0.26.11. Generated C uses ABI 14.

From this directory:

```sh
npm ci --ignore-scripts
npm run generate
npm test
npm run test:neovim
```

The JSON npm dependency is only a test dependency. Integration tests compile its
C parser directly, so npm native-addon install scripts are unnecessary. The tests
compile shared libraries in a temporary directory and remove them afterwards.
They check actual Neovim injections, metadata captures, stream boundaries,
malformed JSON, scalar JSON, incremental updates, and curl.nvim's real renderer.
No requests or other notebook code execute.

Generated `src/parser.c`, `src/grammar.json`, `src/node-types.json`, and headers
are checked in. Consumers can compile the parser without Node.js or npm.

## Try it in Neovim

Build the wrapper from this directory on Linux:

```sh
mkdir -p parser
cc -O2 -shared -fPIC -Isrc src/parser.c -o parser/curljson.so
```

On macOS, use `-dynamiclib` instead of `-shared`. You also need the normal JSON
parser and highlight queries installed, for example through nvim-treesitter.

Use this optional setup, adjusting `root` to your checkout. It registers the
parser and queries, and attaches it to curl.nvim response buffers and `.curljson`
files. Scheduling attachment lets the renderer finish its normal syntax setup.
The snippet leaves notebook source buffers and unrelated JSON buffers alone.

```lua
local root = vim.fn.expand("~/projects/curl.nvim/tree-sitter-curljson")
vim.treesitter.language.add("curljson", { path = root .. "/parser/curljson.so" })
for _, kind in ipairs({ "highlights", "injections" }) do
  local query = table.concat(vim.fn.readfile(root .. "/queries/" .. kind .. ".scm"), "\n")
  vim.treesitter.query.set("curljson", kind, query)
end
vim.filetype.add({ extension = { curljson = "curljson" } })
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "json", "text", "curljson" },
  callback = function(event)
    local buf = event.buf
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.bo[buf].filetype ~= "curljson" and not name:match("Curl notebook output %d+$") then
      return
    end
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return
      end
      vim.bo[buf].syntax = ""
      vim.treesitter.stop(buf)
      vim.treesitter.start(buf, "curljson")
    end)
  end,
})
```

After loading this setup, run a notebook request again or open
`examples/response.curljson`. Use `:InspectTree` to see the wrapper and injected
JSON trees, and `:Inspect` to examine highlight captures.
