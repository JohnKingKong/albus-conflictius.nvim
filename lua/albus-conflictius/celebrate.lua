local M = {}

local banner = require("albus-conflictius.banner")

local LASER_WIDTH = 33

local SPARKLE_PATTERNS = {
  { 5, 14, 24 },
  { 2, 11, 20, 29 },
  { 8, 17, 27 },
  { 4, 13, 22, 31 },
}
local SPARK_CHARS = { "*", ".", "'", "+" }

local function sparkle_row(positions)
  local row = {}
  for i = 1, LASER_WIDTH do
    row[i] = " "
  end
  for i, pos in ipairs(positions) do
    row[pos] = SPARK_CHARS[((i - 1) % #SPARK_CHARS) + 1]
  end
  return table.concat(row)
end

local function laser_row(spark_pos)
  local row = {}
  for i = 1, LASER_WIDTH do
    row[i] = (i == 1 or i == LASER_WIDTH) and "|" or "-"
  end
  row[spark_pos] = "*"
  return table.concat(row)
end

function M.frame_count()
  return 8
end

-- Frames are generated, not hand-drawn: two sparkle rows cycle through a small set of scatter
-- patterns, a "laser" row's spark ping-pongs left-right across the width, and the message
-- border alternates -- around the wizard art, which stays put as the recognizable anchor.
function M.frame(index)
  local i = ((index - 1) % M.frame_count()) + 1

  local lines = {}
  table.insert(lines, sparkle_row(SPARKLE_PATTERNS[((i - 1) % #SPARKLE_PATTERNS) + 1]))
  table.insert(lines, sparkle_row(SPARKLE_PATTERNS[(i % #SPARKLE_PATTERNS) + 1]))
  table.insert(lines, "")

  for _, line in ipairs(banner.art()) do
    table.insert(lines, line)
  end

  table.insert(lines, "")

  local span = LASER_WIDTH - 2
  local cycle = 2 * span
  local pos = (i - 1) % cycle
  if pos >= span then
    pos = cycle - pos
  end
  table.insert(lines, laser_row(pos + 2))
  table.insert(lines, "")

  local border = (i % 2 == 0) and "*~*~*~*~*~*" or "~*~*~*~*~*~"
  local message = (i % 2 == 0) and "ALAKAZAM! ALL CONFLICTS VANISHED!" or "POOF! NOT A SINGLE CONFLICT LEFT!"
  table.insert(lines, border .. "  " .. message .. "  " .. border)

  return lines
end

local function frame_dimensions()
  local frame = M.frame(1)
  local width = 0
  for _, line in ipairs(frame) do
    width = math.max(width, #line)
  end
  return width, #frame
end

-- Plays the animation in an existing buffer/window (resizing the window to fit), advancing one
-- frame every `interval_ms` for `total_frames` steps, then calls `on_done`. Any of <CR>/q/<Esc>
-- skips straight to `on_done`. Safe to call even if the window/buffer disappears mid-playback.
function M.play(bufnr, win, on_done, opts)
  opts = opts or {}
  local total_frames = opts.total_frames or (M.frame_count() * 2)
  local interval_ms = opts.interval_ms or 150

  if vim.api.nvim_win_is_valid(win) then
    local width, height = frame_dimensions()
    vim.api.nvim_win_set_config(win, {
      relative = "editor",
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
    })
  end

  local stopped = false
  local skip_keys = { "<CR>", "q", "<Esc>" }

  local function finish()
    if stopped then
      return
    end
    stopped = true
    for _, key in ipairs(skip_keys) do
      pcall(vim.keymap.del, "n", key, { buffer = bufnr })
    end
    on_done()
  end

  local skip_opts = { buffer = bufnr, silent = true, nowait = true }
  for _, key in ipairs(skip_keys) do
    vim.keymap.set("n", key, finish, skip_opts)
  end

  local function step(index)
    if stopped or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if index > total_frames then
      finish()
      return
    end

    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, M.frame(index))
    vim.bo[bufnr].modifiable = false

    vim.defer_fn(function()
      step(index + 1)
    end, interval_ms)
  end

  step(1)
end

return M
