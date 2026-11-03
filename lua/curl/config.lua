local defaults = {
  shell = { "bash", "--noprofile", "--norc" },
  output_split_direction = "vertical",
}

local mod = { config = vim.deepcopy(defaults) }

function mod.setup(opts)
  if opts == nil then
    opts = {}
  end
  if type(opts) ~= "table" then
    error("curl.setup options must be a table")
  end
  for key in pairs(opts) do
    if key ~= "shell" and key ~= "output_split_direction" then
      error("unknown curl option: " .. tostring(key))
    end
  end
  local shell = opts.shell
  if shell == nil then
    shell = defaults.shell
  end
  if type(shell) ~= "table" or not vim.islist(shell) or #shell == 0 then
    error("shell must be a non-empty argv table")
  end
  for _, arg in ipairs(shell) do
    if type(arg) ~= "string" or arg == "" then
      error("shell arguments must be non-empty strings")
    end
  end
  local direction = opts.output_split_direction
  if direction == nil then
    direction = defaults.output_split_direction
  end
  if direction ~= "vertical" and direction ~= "horizontal" then
    error("output_split_direction must be vertical or horizontal")
  end
  mod.config = {
    shell = vim.deepcopy(shell),
    output_split_direction = direction,
  }
  return mod.config
end

function mod.get(key)
  if key ~= nil then
    return mod.config[key]
  end
  return mod.config
end

return mod
