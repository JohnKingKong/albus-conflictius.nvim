local M = {}

local OURS_START = "^<<<<<<< "
local BASE_START = "^||||||| "
local SEPARATOR = "^=======$"
local THEIRS_END = "^>>>>>>> "

local function slice(lines, from_idx, to_idx)
  local out = {}
  for i = from_idx, to_idx do
    table.insert(out, lines[i])
  end
  return out
end

-- Scans `lines` for diff3-style (or plain) conflict marker blocks and returns each as a hunk
-- descriptor. Only understands the standard git marker set; a hunk with no `|||||||` separator
-- still parses (has_base=false), since the wand can't classify it but the caller still needs to
-- know it exists so it's reported as a remaining conflict rather than silently dropped.
function M.parse_hunks(lines)
  local hunks = {}
  local i = 1
  while i <= #lines do
    if lines[i]:match(OURS_START) then
      local start_idx = i
      local ours_start = i + 1
      local j = ours_start
      while j <= #lines and not lines[j]:match(BASE_START) and not lines[j]:match(SEPARATOR) do
        j = j + 1
      end
      local ours = slice(lines, ours_start, j - 1)

      local base = nil
      local has_base = false
      if j <= #lines and lines[j]:match(BASE_START) then
        has_base = true
        local base_start = j + 1
        local k = base_start
        while k <= #lines and not lines[k]:match(SEPARATOR) do
          k = k + 1
        end
        base = slice(lines, base_start, k - 1)
        j = k
      end

      -- j now points at the "=======" separator line
      local theirs_start = j + 1
      local m = theirs_start
      while m <= #lines and not lines[m]:match(THEIRS_END) do
        m = m + 1
      end
      local theirs = slice(lines, theirs_start, m - 1)

      table.insert(hunks, {
        start_idx = start_idx,
        end_idx = m,
        ours = ours,
        base = base,
        theirs = theirs,
        has_base = has_base,
      })

      i = m + 1
    else
      i = i + 1
    end
  end
  return hunks
end

local function lines_equal(a, b)
  if #a ~= #b then
    return false
  end
  for idx = 1, #a do
    if a[idx] ~= b[idx] then
      return false
    end
  end
  return true
end

-- Decides whether a single hunk can be auto-resolved: true when only one side actually diverged
-- from base, or when both sides independently converged on identical text. Returns false (leave
-- markers as-is) when both sides genuinely diverge differently, or when there's no base to compare
-- against at all (plain diff2-style marker, no `|||||||`).
function M.resolve_hunk(hunk)
  if not hunk.has_base then
    return false
  end

  local ours_changed = not lines_equal(hunk.ours, hunk.base)
  local theirs_changed = not lines_equal(hunk.theirs, hunk.base)

  if lines_equal(hunk.ours, hunk.theirs) then
    return true, hunk.ours
  elseif ours_changed and not theirs_changed then
    return true, hunk.ours
  elseif theirs_changed and not ours_changed then
    return true, hunk.theirs
  else
    return false
  end
end

function M.resolve_lines(lines)
  local hunks = M.parse_hunks(lines)
  local new_lines = {}
  local resolved_count = 0
  local remaining_count = 0
  local cursor = 1

  for _, hunk in ipairs(hunks) do
    for i = cursor, hunk.start_idx - 1 do
      table.insert(new_lines, lines[i])
    end

    local resolved, content = M.resolve_hunk(hunk)
    if resolved then
      resolved_count = resolved_count + 1
      for _, line in ipairs(content) do
        table.insert(new_lines, line)
      end
    else
      remaining_count = remaining_count + 1
      for i = hunk.start_idx, hunk.end_idx do
        table.insert(new_lines, lines[i])
      end
    end

    cursor = hunk.end_idx + 1
  end

  for i = cursor, #lines do
    table.insert(new_lines, lines[i])
  end

  return new_lines, resolved_count, remaining_count
end

function M.resolve_content(content)
  local lines = vim.split(content, "\n", { plain = true })
  local new_lines, resolved_count, remaining_count = M.resolve_lines(lines)
  return table.concat(new_lines, "\n"), resolved_count, remaining_count
end

function M.has_conflict_markers(content)
  for line in content:gmatch("([^\n]*)\n?") do
    if line:match(OURS_START) then
      return true
    end
  end
  return false
end

return M
