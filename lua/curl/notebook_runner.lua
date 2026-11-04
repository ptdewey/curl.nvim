local M = {}

local function read_requests(path)
  local file = io.open(path, "rb")
  if not file then
    return {}
  end
  local data = file:read("*a") or ""
  file:close()
  local fields = vim.split(data, "\0", { plain = true })
  local requests, index = {}, 1
  while index < #fields do
    local count = tonumber(fields[index])
    if not count or count < 0 or count % 1 ~= 0 or index + count >= #fields then
      break
    end
    local argv = {}
    for offset = 1, count do
      argv[offset] = fields[index + offset]
    end
    requests[#requests + 1] = require("curl.request").parse(argv)
    index = index + count + 1
  end
  return requests
end

local function collect(chunks, data)
  chunks[#chunks + 1] = table.concat(data, "\n")
end

local function write_private_file(contents)
  local path = vim.fn.tempname()
  local fd, open_error = vim.uv.fs_open(path, "wx", 384)
  if not fd then
    return nil, open_error
  end
  local ok, write_error = pcall(vim.uv.fs_write, fd, contents, 0)
  vim.uv.fs_close(fd)
  if not ok or write_error ~= #contents then
    vim.uv.fs_unlink(path)
    return nil, ok and "failed to write file" or write_error
  end
  return path
end

function M.start(options, callback)
  if type(options) ~= "table" or type(options.script) ~= "string" then
    return nil, "script must be a string"
  end
  if type(options.setup) ~= "string" or type(options.body) ~= "string" then
    return nil, "setup and body must be strings"
  end
  if type(options.cwd) ~= "string" or options.cwd == "" then
    return nil, "cwd must be a non-empty string"
  end
  local shell = options.shell or { "bash", "--noprofile", "--norc" }
  if type(shell) ~= "table" or #shell == 0 then
    return nil, "shell must be a non-empty argv list"
  end
  local metadata_path, metadata_error = write_private_file("")
  if not metadata_path then
    return nil, "failed to create request metadata file: " .. tostring(metadata_error)
  end
  local script = string.format(
    'curl() {\n  command printf "%%s\\0" "$#" "$@" >> %s\n  command curl --silent --show-error "$@"\n}\n',
    vim.fn.shellescape(metadata_path)
  )
  if options.setup ~= "" then
    script = script .. options.setup .. "\n"
  end
  script = script .. "case $? in 0) ;; *) exit $? ;; esac\n" .. options.body
  local path, path_error = write_private_file(script)
  if not path then
    vim.uv.fs_unlink(metadata_path)
    return nil, "failed to write temporary script: " .. tostring(path_error)
  end
  local command = vim.deepcopy(shell)
  command[#command + 1] = path
  local stdout, stderr = {}, {}
  local started = vim.uv.hrtime()
  local completed = false
  local job_id
  local handle = {}

  local function finish(exit_code, cancelled)
    if completed then
      return
    end
    completed = true
    local requests = read_requests(metadata_path)
    vim.uv.fs_unlink(metadata_path)
    vim.uv.fs_unlink(path)
    local result = {
      stdout = table.concat(stdout),
      stderr = table.concat(stderr),
      exit_code = exit_code,
      elapsed = (vim.uv.hrtime() - started) / 1e9,
      cancelled = cancelled,
      requests = requests,
    }
    vim.schedule(function()
      callback(result)
    end)
  end

  local ok, result = pcall(vim.fn.jobstart, command, {
    cwd = options.cwd,
    env = { BASH_ENV = "" },
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      collect(stdout, data)
    end,
    on_stderr = function(_, data)
      collect(stderr, data)
    end,
    on_exit = function(_, code)
      finish(code, handle.cancelled == true)
    end,
  })
  if not ok or result <= 0 then
    vim.uv.fs_unlink(metadata_path)
    vim.uv.fs_unlink(path)
    return nil, "failed to start shell: " .. tostring(result)
  end
  job_id = result
  handle.cancel = function()
    if not completed and not handle.cancelled then
      handle.cancelled = true
      vim.fn.jobstop(job_id)
    end
  end
  vim.fn.chanclose(job_id, "stdin")
  return handle
end

return M
