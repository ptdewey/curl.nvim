# curl.nvim

Run the shell request block under your cursor and inspect its response in a
scratch split. Keep notebooks as ordinary files in your project, usually `.sh`.
The plugin does not manage collections, register a source filetype, or install
keymaps.

This is a notebook-only fork of [curl.nvim](https://github.com/oysandvik94/curl.nvim).

## Requirements

- Neovim 0.11 or newer on Linux/macOS.
- Bash by default, or an explicitly configured compatible shell.
- curl when your notebook commands use it.

JSON formatting uses Neovim's JSON support; jq is not required. Run
`:checkhealth curl` to check the configured shell and curl availability.

## Usage

Add the plugin to Neovim's runtime path with your plugin manager. Map the Lua API
directly; `setup()` is not required when using the default configuration:

```lua
vim.keymap.set("n", "<leader>rr", function()
  require("curl").run()
end, { desc = "Run request block" })

vim.keymap.set("n", "<leader>rc", function()
  require("curl").cancel()
end, { desc = "Cancel request" })
```

If you prefer commands, call `require("curl").setup()` to register `:CurlRun` and
`:CurlCancel`. Both act on the current source buffer. No Enter mapping is added.

Open [examples/notebook.sh](examples/notebook.sh) to try GET, JSON POST, HTTP-error,
and cancellation scenarios against public httpbin. Do not send real secrets.
[examples/requests.sh](examples/requests.sh) shows a local-service notebook.

## Notebook format

```sh
ENV=local
case "$ENV" in
  local) BASE_URL=http://localhost:8000 ;;
  dev) BASE_URL=https://dev.example.invalid ;;
  *) printf 'Unknown environment: %s\n' "$ENV" >&2; exit 1 ;;
esac

### Read application
APPLICATION_ID=48047
curl "$BASE_URL/applications/$APPLICATION_ID"

### Create application
curl "$BASE_URL/applications" \
  --header 'Content-Type: application/json' \
  --data '{
    "name": "Example application"
  }'
```

Everything before the first marker is shared setup. A marker starts at column
one with `###`, followed by whitespace and a title, or the end of the line.
Matching lines are reserved even inside quoted strings and heredocs. Indented
markers and `###word` are ordinary source text. Keep quotes, heredocs, and shell
control structures within one section.

The marker and following lines up to the next marker belong to that request,
including blank lines. A cursor in setup, a file without markers, or an empty or
comment-only block produces a message without launching a shell.

Each run snapshots the current buffer, including unsaved edits. It executes
setup once and only the selected block in one fresh asynchronous shell. The
plugin runs all code in that block, not just its curl call. Assignments in other
blocks or previous invocations do not carry over.

A final nonzero setup status or explicit `exit` prevents request execution.
Check intermediate failures yourself or use an appropriate shell option; the
plugin does not enable `set -e`. Source text is not rewritten: use normal shell
quotes, continuations, variables, and heredocs. Single-quoted bodies are literal.

Relative paths resolve against the notebook file's directory, or Neovim's current
directory for an unnamed buffer. Neither file extension nor filetype affects
execution. Opening, editing, and saving a buffer never execute it or autosave it.
Running a whole notebook directly in a terminal may execute every request; the
plugin's run action selects only one block.

## Results and cancellation

With `mini.notify` configured before running a request, a notification shows a
spinner and elapsed seconds, then disappears when the request ends. Without it,
the plugin sends one ordinary `vim.notify` message when the request starts.
No percentage is shown because arbitrary shell requests have no known total.

All scripts share one temporary scratch response buffer and reuse its split.
Closing its last window discards the response. On Neovim versions with
SessionWritePre, saving a session (including via `:restart`) also discards the
response and its splits so they are not restored. Source buffers are unaffected.
Each finished request replaces the displayed result with its title, request URLs,
supplied request headers, elapsed time, stdout, and stderr. URLs and headers reflect
shell expansion and are grouped by curl invocation. Only explicitly supplied headers
are shown, not curl-generated headers; `--header @file` remains a file reference.
HTTP status appears only when returned in response headers (for example, with
`--include`). Successful shell exit codes are hidden; failures show `Exit code`
and cancellations are marked separately. Both streams remain available after
failure. JSON is pretty-printed and receives
automatic JSON highlighting; metadata and stderr have separate highlighting.
Other text, invalid JSON, and empty responses remain inspectable.
The display normalizes CRLF and bare carriage returns to newlines and removes
ANSI color/control sequences and terminal title escapes from both streams.

Use curl's `--include` when you want headers. HTTP errors and process failures
are different: a 4xx/5xx response can have exit status zero unless you supply
`--fail` or a related option.

Inside the notebook shell, a `curl` function supplies `--silent --show-error` by
default: no progress meter, but real errors remain visible. Your arguments follow
these defaults, so `curl --no-silent` restores progress and `--no-show-error`
suppresses errors. Use `command curl` or an explicit executable path to bypass
the defaults entirely, or redefine the function in shared setup. Executable
selection still follows PATH. These defaults apply to setup and the selected
block only; running the notebook directly in a terminal is unchanged. The same
function captures URL and header arguments for display; bypassing it also skips
request metadata capture. URLs are the supplied arguments, not redirect targets
or URLs with curl-generated query parameters. Options loaded from curl config
files are not captured.

One execution may run per source buffer. Cancel or wait before starting another.
`require("curl").cancel()` cancels the current source's request; pass a source
buffer number to cancel another. `:CurlCancel` is the current-buffer equivalent.
Cancellation terminates the shell and its request children but cannot undo
server-side effects. Wiping a source buffer cancels its active run but leaves
the shared response buffer intact.

## Configuration

These are the complete defaults. Shell arguments replace the default argv rather
than merging with it; `setup()` without options resets the defaults.

```lua
require("curl").setup({
  shell = { "bash", "--noprofile", "--norc" },
  output_split_direction = "vertical",
})
```

Use `"horizontal"` for a horizontal response split. Configure the shell as an argv
list without `-c` or a script argument; the runner appends its temporary script's
path. An unavailable configured shell is an error, with no dialect fallback.
The public API consists of `setup(opts?)`, `run()`, and `cancel(bufnr?)`.

## Safety and persistence

Run only trusted notebooks. Setup and request blocks are executable shell code,
including substitutions and sourced files. No `.env` file is sourced implicitly.
The child inherits the editor's environment, but notebook assignments cannot
mutate Neovim's environment or survive the child. This is not a sandbox for
filesystem changes, network calls, or other external effects.

The default Bash invocation disables startup files, including `BASH_ENV`.
Execution uses a private temporary script and expanded-argument metadata file,
both removed after completion, failure, or cancellation. No response history or
expanded commands are persisted.
Notebook files you save are ordinary plaintext, including any literal secrets.

## Migration from earlier versions

This fork no longer provides legacy execution, collections, scratch-file storage,
`.curl` filetype registration, or default mappings. `CurlOpen`, `CurlCollection`,
`CurlClose`, and their Lua APIs are removed. Existing files under
`stdpath("data")/curl_cache` are left untouched; open them manually and save them
where you want. No collection files are read, migrated, or deleted by the plugin.

Replace `execute_notebook()` or `execute_curl()` mappings with `run()`, and
`cancel_notebook()` with `cancel()`. Rename `notebook_shell` to `shell`. Remove
`notebook_mode`, `mappings`, `open_with`, `default_flags`, `curl_binary`, and
`show_request_duration_limit` from configuration; unknown options are rejected.
Notebook execution is now the only execution mode.

Replace legacy `---name=value` directives with shell assignments, put shared setup
above the first `###` marker, and mark each request. Add shell quotes around JSON
and backslashes for continued commands. `.curl` files with valid notebook content
can still run through your mapping, but they receive no special filetype treatment.

## Development

Run `make test` for the plugin suite. See [CONTRIBUTING.md](CONTRIBUTING.md) for
module boundaries and test conventions.
