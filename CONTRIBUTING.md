# Contributing

## Scope

curl.nvim runs a marker-delimited shell notebook block from the current buffer.
Files belong to the user and their project. The plugin does not manage notebook
storage, register source filetypes, or provide default keymaps.

Preserve shell source rather than adding an interpolation or command-rewriting
language. Shared setup and the selected block run in one isolated shell; neither
other blocks nor previous invocations contribute shell state.

## Modules

- `init.lua`: public `setup`, `run`, and `cancel` API and command registration.
- `api.lua`: snapshot the source buffer, select the block, and track its execution
  and cancellation lifecycle. No collection or legacy execution paths.
- `notebook.lua`: pure source-range extraction using `###` markers.
- `notebook_runner.lua`: asynchronous shell process, private temporary script,
  working directory, stream capture, exit status, elapsed time, and cancellation.
- `buffers.lua`: source-keyed scratch response splits, formatting, and highlighting.
- `config.lua`: shell argv and response split direction.
- `notifications.lua`: user-facing notifications.
- `health.lua`: configured-shell and optional curl availability checks.

## Tests

Run `make test`, or `make test_file FILE=tests/tests/test_notebook.lua` for one file.
The Makefile downloads mini.nvim on the first run. Tests must use local fixtures
or fake executables, not public HTTP services or the user's actual config/data.
Use temporary files and restore mocked functions even when assertions fail.

Keep regression coverage for unsaved source, arbitrary filetypes, setup isolation,
source fidelity, failure output, process-tree cancellation, overlapping sources,
and response-buffer reuse. Removing a feature should remove only its own tests,
not unrelated notebook assertions. Add a reproducer for bug fixes.

