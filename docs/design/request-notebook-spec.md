# Shell-compatible request notebooks

Status: historical design spec, implemented with later notebook-only simplification.
The transition-mode and collection-compatibility proposals below are superseded:
source files are user-managed, any extension works, and `require("curl").run()`
is the sole run action. See `README.md` for the current API and configuration.

## Intent

Keep the workflow of a `.http` file: a checked-in notebook of named requests,
with one request executed under the cursor. Write the requests as ordinary shell
curl commands so they are easier to share and paste into a terminal.

The main use case is switching between local and dev services while trying
different request payloads. Select the environment with a variable near the top
of the file, rather than maintaining `http-client.env.json` or using an editor
environment picker.

Existing examples in `~/workspace/gradient/` establish the workload:

- `decision.http`: 29 independent decision requests with shared base URLs,
  cache-bypass headers, and optional JSON payloads.
- `otb.http`: 47 named scenarios, including large, multiline JSON bodies.
- `roe.http`: request-local customer IDs and several service endpoints.
- `store.http`: small GET requests with shared service URLs.
- `stage.http`: shared endpoint variables and an occasional prompted ID.

Prompted values are existing usage, not a requirement for the first version.
Use a block-local shell assignment instead.

## Confirmed requirements

1. Keep multiple named requests in one editable file.
2. Execute the request block under the cursor without executing other blocks.
3. Use shell-compatible curl commands, including normal quoting, line
   continuations, headers, and multiline bodies.
4. Put shared setup above the requests. A top-of-file environment selector
   chooses local or dev and derives the appropriate service URLs.
5. Allow request-local assignments, such as an application or customer ID.
6. Let the shell expand variables. Do not require JSON environment files,
   `{{variable}}` templates, or curl.nvim's `---name=value` directives.
7. Run shared setup and the selected block in one fresh shell per invocation.
   Do not mutate Neovim's environment or retain shell state between runs.
8. Read the current buffer, including unsaved changes.

The file does not have to be executable as a complete script. Individual
commands must be valid shell; commands referencing shared variables assume that
the recipient also has the relevant setup. Producing a self-contained, expanded
command for sharing is a possible later feature.

## File format

Use `.curl` files. Everything before the first `###` marker is shared setup.
Each marker introduces a request block extending to the next marker or EOF.
The rest of the marker line names the request.

```sh
ENV=local

case "$ENV" in
  local)
    DECISIONS_BASE_URL=http://localhost:8099/api/v1/decisions/applications
    ;;
  dev)
    DECISIONS_BASE_URL=https://decisions.dev.example.com/api/v1/decisions/applications
    ;;
  *)
    printf 'Unknown environment: %s\n' "$ENV" >&2
    exit 1
    ;;
esac

### Long app C0

curl --silent --show-error \
  --request POST "$DECISIONS_BASE_URL/37199" \
  --header 'X-Gradient-Cache-Bypass: true'

### BAV with injected payload

APPLICATION_ID=48047

curl --silent --show-error \
  --request POST "$DECISIONS_BASE_URL/$APPLICATION_ID" \
  --header 'Content-Type: application/json' \
  --header 'X-Gradient-Cache-Bypass: true' \
  --data '{
    "requestType": "lease-bav"
  }'
```

Blank lines do not delimit requests. Comments, assignments, and multiline JSON
belong to their containing block. Every setup section and request block must be
a complete shell fragment; quotes, heredocs, and control structures must not
span block boundaries.

Proposed first-version delimiter rule: recognize `###` at column one, followed
by whitespace and a title, or by the end of the line. Reserve matching lines
for delimiters even inside quoted bodies or heredocs. Document this restriction
rather than requiring a shell parser. Embedded `###` elsewhere is ordinary text.

Preserve the selected source text and newlines. Do not strip comments, infer
JSON boundaries, insert quotes, remove backslashes, or translate assignments.
Single-quoted bodies remain literal. Use ordinary shell quoting or an unquoted
heredoc when interpolation inside a body is wanted.

## Execution contract

1. Snapshot the buffer and cursor position on an explicit run action.
2. Find the containing request block by markers, not by searching for `curl`
   or by splitting on blank lines.
3. Build a script from the shared setup and that block only, separated by a
   newline. Never include earlier request blocks to obtain their assignments.
4. Start one asynchronous shell process for that script. Setup assignments
   remain available to the selected request without requiring `export`.
5. Collect stdout, stderr, exit status, and elapsed time. Keep Neovim responsive.
6. Display the result associated with the originating buffer and block.

The plugin selects a block, not individual shell commands within it. Authors
should put one intended HTTP request in each block. If a block contains multiple
curl calls or a loop, executing it runs all of that code. Shared setup is also
executable code and runs once per invocation; it should not contain requests.

Shell failures must remain visible. A nonzero exit from shared setup must not
lead to request execution. Ordinary shell failure rules still apply: authors
must check setup commands whose failures should abort the script, or use an
appropriate shell option. The plugin cannot infer failure from an unchecked
command followed by a successful one.

### Proposed first-version defaults

These details complete the behavior but have not been separately confirmed:

- Use an explicitly configured non-interactive shell, defaulting to Bash without
  startup files. Do not silently fall back to a different shell dialect.
- Use the request file's directory as the working directory, so relative body
  files and sourced setup files have a stable meaning. Use Neovim's current
  directory for an unnamed buffer, and show the chosen directory in diagnostics.
- A cursor on a marker selects the block it introduces. Any line after that
  marker, including blank lines, belongs to the same block until the next marker.
- A cursor in shared setup, an empty block, or a file without markers produces
  a useful message and starts no process. Never fall back to running everything.
- Allow only one active execution per source buffer. A second run asks the user
  to cancel or wait; it does not silently replace a running request.
- Provide explicit cancellation and mark the result as cancelled. Terminate the
  shell and its request children. Cancellation does not undo server-side effects.
- Opening, editing, or saving a file never executes it. Do not require autosaving
  the file to run a request.

## Response display

Proposed first-version UI: reuse a scratch response split, identify the request
by its block title, and show process exit status and elapsed time. Preserve
stdout and stderr, including output produced before a failure. Preserve newline
boundaries when collecting process output.

Pretty-print JSON when possible; otherwise show the original response. Empty
bodies and invalid JSON must not make the response disappear. HTTP errors and
curl transport errors are different outcomes: a 4xx response may still have a
successful process exit unless the author supplied `--fail` or a related flag.

Status and headers are useful, but automatic capture needs a separate design
decision. For the initial version, authors can include curl's `--include` flag
to display them. A later metadata-capture mechanism must not corrupt body bytes,
change redirect or failure behavior, or append flags to an arbitrary shell block.
Do not silently inject `-sSL`, `default_flags`, or other request options in this
mode. The file should describe the request that actually runs.

## Safety and persistence

Treat these files as executable shell code, not passive HTTP documents. Running
a block also runs its setup, including any command substitution or sourced code.
Only execute trusted files, and do not auto-source a project `.env` file or any
other setup the author did not request in the notebook.

Inherit the editor's environment for the child process, but keep notebook
assignments isolated to that child. A fresh shell prevents variable leakage; it
does not sandbox filesystem changes, network calls, or other external effects.

Do not introduce automatic response history or persist expanded commands,
tokens, or response bodies. Any temporary files used for execution or capture
must be private and cleaned up after success, failure, or cancellation. Existing
collection persistence is separate from this feature. Literal secrets saved in
a notebook are still plaintext secrets.

## Fit with the existing fork

The inspected working copy already contains pending whole-buffer shell support.
Preserve those edits while implementing this spec. Whole-buffer execution can
remain an explicitly separate action, but it must not override the notebook's
run-under-cursor action, even when `execute_whole_buffer` is enabled.

| Existing code | Change needed for notebook mode |
| --- | --- |
| `lua/curl/parser.lua:90-160` | Replace blank-line/curl-based selection and command rewriting with source-range extraction by markers. Keep selection separate from highlighting. |
| `lua/curl/api.lua:96-135` | Reuse or adapt asynchronous execution; preserve output newlines, retain both streams on failure, and track cancellation. |
| `lua/curl/api.lua:145-200` | Compose setup plus selected block instead of the entire buffer. Bypass legacy directive translation and prevent `execute_whole_buffer` from hijacking notebook execution. |
| `lua/curl/buffers.lua:121-130` | Do not call the `vim.env`-mutating variable helper in notebook mode. |
| `lua/curl/shell_utils.lua:43-55` | Make shell choice explicit and predictable for notebook mode. |
| `lua/curl/output_parser.lua` | Preserve non-JSON output and separate response formatting from execution. |
| `ftplugin/curl.lua:5-18` | Wire the notebook run action; remove or make optional the edit-triggered autosave. |
| `tests/tests/`, `README.md`, `doc/curl.nvim.txt` | Add notebook tests and document shell semantics, trust, and migration. |

This spec does not promise compatibility with legacy `.curl` syntax. If retained,
legacy parsing should be an explicit mode, not a heuristic mixed into notebook
execution. A custom curl binary must not require rewriting arbitrary shell source;
users can select a binary through normal shell setup while that API is decided.

## Alternatives and recommendation

| Approach | Benefit | Cost |
| --- | --- | --- |
| Existing command-under-cursor mode | Smallest change; existing collections still work | Blank-line boundaries, custom variable directives, and parent-environment mutation do not meet this workflow. |
| Existing whole-buffer mode | Real shell semantics; already present in the fork | Executes other scenarios, which is unsafe as the normal notebook action. |
| Shared setup plus selected marker block | Preserves the HTTP-notebook workflow and ordinary shell syntax | Requires block extraction, execution isolation, and explicit delimiter limitations. |

Choose shared setup plus the selected block for this hard fork. The parsing and
execution changes are reversible; changing the meaning of existing `.curl`
files is the compatibility risk. Prefer an explicit notebook mode during the
transition. The strongest reason to keep legacy mode is existing collections,
not a need to extend its interpolation language.

## Acceptance criteria

Use fake curl executables or a local test server. Tests must not contact dev,
production, or any example service.

- A file with three blocks executes setup once and only the middle block when
  the cursor is anywhere in that block, including its header, body, or blank lines.
- Editing `ENV=local` to `ENV=dev` changes the selected URL on the next invocation
  without saving the file or selecting an environment through an editor UI.
- Assignments in the selected block override setup for that invocation. Variables
  assigned in another block or a previous invocation are unavailable unless
  independently present in the inherited editor environment.
- Neovim's environment is unchanged after successful and failed runs.
- Quoting, backslash continuations, multiline JSON, apostrophes in JSON values,
  and heredocs survive extraction and reach the shell without rewriting.
- The documented delimiter rule behaves consistently, including the reserved-line
  limitation inside multiline bodies.
- Missing markers, setup-only cursor positions, and empty blocks do not launch
  a shell. The final block works without a trailing newline.
- An explicit setup failure prevents the selected request from executing.
- Unsaved buffers run their current content. Paths containing spaces work, and
  relative paths resolve against the documented working directory.
- Slow requests do not block editing. Cancellation stops the request process
  tree, and overlapping runs cannot overwrite an unrelated result.
- Multiline stdout and stderr retain their line boundaries. Failures retain both
  streams. JSON, text, empty responses, and HTTP error bodies remain inspectable.
- Opening, editing, or saving a notebook launches no process. Tests cover the
  interaction with the existing `execute_whole_buffer` option.

## Out of scope

- Automatically converting the existing `.http` files.
- Making the whole notebook a standalone runnable script or adding a CLI runner.
- Environment pickers, JSON environment files, and a custom interpolation syntax.
- Response-driven request chaining, assertions, or a test-runner DSL.
- New collections management, response history, or a persistent database.
- Resolving variables into a self-contained command for copying.
- Windows shell support and a full shell-aware delimiter parser.

## Implementation slices

1. Add pure block extraction with tests for setup, cursor positions, markers,
   and verbatim source preservation.
2. Execute extracted fragments in an isolated shell with deterministic cwd,
   output collection, and failure tests. Keep unrelated working-copy edits.
3. Wire the buffer action and response split; cover cancellation and concurrent
   invocations using local fixtures.
4. Document the format and migrate one representative request file manually to
   validate the workflow before expanding scope.
