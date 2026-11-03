local M = {}

local function is_marker(line)
  return line == "###" or line:match("^###%s+%S") ~= nil
end

local function is_empty_block(lines, first, last)
  for index = first, last do
    local line = lines[index]
    if not line:match("^%s*$") and not line:match("^%s*#") then
      return false
    end
  end
  return true
end

local function join_lines(lines, first, last)
  local result = {}
  for index = first, last do
    result[#result + 1] = lines[index]
  end
  return table.concat(result, "\n")
end

function M.extract(lines, cursor_line)
  local markers = {}
  for index, line in ipairs(lines) do
    if is_marker(line) then
      markers[#markers + 1] = index
    end
  end

  if #markers == 0 then
    return nil, "no request markers found"
  end

  local selected
  for index, marker_line in ipairs(markers) do
    local end_line = markers[index + 1] and markers[index + 1] - 1 or #lines
    if cursor_line >= marker_line and cursor_line <= end_line then
      selected = index
      break
    end
  end

  if not selected then
    return nil, "cursor is in shared setup"
  end

  local marker_line = markers[selected]
  local end_line = markers[selected + 1] and markers[selected + 1] - 1 or #lines
  local first_body_line = marker_line + 1
  if is_empty_block(lines, first_body_line, end_line) then
    return nil, "request block is empty"
  end

  local setup_end = markers[1] - 1
  local setup = join_lines(lines, 1, setup_end)
  local body = join_lines(lines, first_body_line, end_line)
  local title = lines[marker_line]:match("^###%s*(.-)%s*$") or ""
  return {
    setup = setup,
    body = body,
    script = setup == "" and body or setup .. "\n" .. body,
    title = title,
    marker_line = marker_line,
    end_line = end_line,
  }
end

return M
