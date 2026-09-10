local M = {}

local banner = require("albus-conflictius.banner")

local LASER_WIDTH = 33

-- `default = true` so these only apply when the colorscheme/user hasn't already defined them --
-- unlike the ours/theirs hunk highlights, these are meant to be vividly colorful regardless of
-- colorscheme (it's fireworks, not a serious UI element), so they're explicit hex, not Diff* links.
local SPARK_HL = {
  "AlbusConflictiusSpark1",
  "AlbusConflictiusSpark2",
  "AlbusConflictiusSpark3",
  "AlbusConflictiusSpark4",
  "AlbusConflictiusSpark5",
  "AlbusConflictiusSpark6",
}
vim.api.nvim_set_hl(0, "AlbusConflictiusSpark1", { default = true, fg = "#ff5f5f" })
vim.api.nvim_set_hl(0, "AlbusConflictiusSpark2", { default = true, fg = "#ffd75f" })
vim.api.nvim_set_hl(0, "AlbusConflictiusSpark3", { default = true, fg = "#5fd7ff" })
vim.api.nvim_set_hl(0, "AlbusConflictiusSpark4", { default = true, fg = "#ff5fff" })
vim.api.nvim_set_hl(0, "AlbusConflictiusSpark5", { default = true, fg = "#5fff5f" })
vim.api.nvim_set_hl(0, "AlbusConflictiusSpark6", { default = true, fg = "#af87ff" })
vim.api.nvim_set_hl(0, "AlbusConflictiusLaser", { default = true, fg = "#ff875f" })
vim.api.nvim_set_hl(0, "AlbusConflictiusBorder", { default = true, fg = "#d7af5f" })

local NAMESPACE = vim.api.nvim_create_namespace("albus-conflictius-celebrate")

-- The top row is deliberately denser than the bottom one -- a "bigger" burst up high, thinning
-- out below it, rather than two identical rows.
local SPARKLE_PATTERNS_TOP = {
  { 3, 6, 9, 12, 15, 18, 21, 24, 27, 30 },
  { 2, 5, 8, 11, 14, 17, 20, 23, 26, 29, 32 },
  { 4, 7, 10, 13, 16, 19, 22, 25, 28, 31 },
  { 2, 4, 8, 11, 15, 18, 21, 24, 27, 30, 32 },
}
local SPARKLE_PATTERNS_BOTTOM = {
  { 5, 14, 24 },
  { 2, 11, 20, 29 },
  { 8, 17, 27 },
  { 4, 13, 22, 31 },
}
local SPARK_CHARS = { "*", ".", "'", "+", "x", "o" }

local WIZARD_ART = banner.art()
local WIZARD_WIDTH = 0
for _, line in ipairs(WIZARD_ART) do
  WIZARD_WIDTH = math.max(WIZARD_WIDTH, #line)
end

local function center_pad(width)
  return string.rep(" ", math.max(0, math.floor((WIZARD_WIDTH - width) / 2)))
end

-- Returns the row text (centered against the wizard's width) plus a list of {col (0-based),
-- hl_group} marks for its special characters, computed at construction time rather than by
-- re-scanning the rendered text afterward.
local function sparkle_row(positions)
  local row = {}
  for i = 1, LASER_WIDTH do
    row[i] = " "
  end
  local marks = {}
  local pad = center_pad(LASER_WIDTH)
  for i, pos in ipairs(positions) do
    local char_index = ((i - 1) % #SPARK_CHARS) + 1
    row[pos] = SPARK_CHARS[char_index]
    table.insert(marks, { col = #pad + pos - 1, hl_group = SPARK_HL[char_index] })
  end
  return pad .. table.concat(row), marks
end

local function laser_row(spark_pos)
  local row = {}
  for i = 1, LASER_WIDTH do
    row[i] = (i == 1 or i == LASER_WIDTH) and "|" or "-"
  end
  row[spark_pos] = "*"
  local pad = center_pad(LASER_WIDTH)
  return pad .. table.concat(row), { { col = #pad + spark_pos - 1, hl_group = "AlbusConflictiusLaser" } }
end

M.MESSAGES = {
  "ALAKAZAM! ALL CONFLICTS VANISHED!",
  "POOF! NOT A SINGLE CONFLICT LEFT!",
  "HOCUS POCUS! CONFLICTS BE GONE!",
  "HARMONY RESTORED -- MERGE COMPLETE!",
  "HOORAY! THE REPO IS AT PEACE!",
}

function M.random_message()
  return M.MESSAGES[math.random(#M.MESSAGES)]
end

function M.frame_count()
  return 8
end

-- Frames are generated, not hand-drawn: a dense sparkle row up top and a lighter one below it
-- cycle through scatter patterns, and a "laser" row's spark ping-pongs left-right, around a
-- message whose border alternates. Everything narrower than the (static) wizard art is centered
-- against it. `message` is fixed for the whole playback (chosen once by `play`/`random_message`),
-- not re-picked per frame. This plays inside the dashboard's own window at its current size,
-- never resized to fit anything.
-- Returns (lines, highlights) -- highlights is a list of {row, col, hl_group} (0-based, single
-- character wide) plus border ranges, applied by `play` as extmarks.
function M.frame(index, message)
  message = message or M.MESSAGES[1]
  local i = ((index - 1) % M.frame_count()) + 1

  local lines = {}
  local highlights = {}

  local function push(text, marks)
    local row = #lines
    table.insert(lines, text)
    if marks then
      for _, m in ipairs(marks) do
        table.insert(highlights, { row = row, col = m.col, hl_group = m.hl_group })
      end
    end
  end

  local top, top_marks = sparkle_row(SPARKLE_PATTERNS_TOP[((i - 1) % #SPARKLE_PATTERNS_TOP) + 1])
  push(top, top_marks)
  local bottom, bottom_marks = sparkle_row(SPARKLE_PATTERNS_BOTTOM[(i % #SPARKLE_PATTERNS_BOTTOM) + 1])
  push(bottom, bottom_marks)
  push("")

  for _, line in ipairs(WIZARD_ART) do
    push(line)
  end

  push("")

  local span = LASER_WIDTH - 2
  local cycle = 2 * span
  local pos = (i - 1) % cycle
  if pos >= span then
    pos = cycle - pos
  end
  local laser_line, laser_marks = laser_row(pos + 2)
  push(laser_line, laser_marks)
  push("")

  local border = (i % 2 == 0) and "*~*~*~*~*~*" or "~*~*~*~*~*~"
  local message_line = border .. "  " .. message .. "  " .. border
  local pad = center_pad(#message_line)
  local right_border_start = #pad + #border + 2 + #message + 2
  push(pad .. message_line, {
    { col = #pad, hl_group = "AlbusConflictiusBorder", col_end = #pad + #border },
    { col = right_border_start, hl_group = "AlbusConflictiusBorder", col_end = right_border_start + #border },
  })

  return lines, highlights
end

local function apply_highlights(bufnr, highlights)
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  for _, mark in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, mark.row, mark.col, {
      end_col = mark.col_end or (mark.col + 1),
      hl_group = mark.hl_group,
    })
  end
end

-- Plays the animation in an existing buffer/window at whatever size it already is -- it never
-- resizes the window, so there's nothing here that can leave a stale border/title artifact behind
-- or throw on a too-small terminal. Advances one frame every `interval_ms` for `total_frames`
-- steps, then calls `on_done`. Any of <CR>/q/<Esc> skips straight to `on_done`. If rendering a
-- frame ever errors for any reason, that's treated as "done" rather than silently hanging forever
-- with the caller never finding out. The celebration message is chosen once (random, or
-- `opts.message` for tests) and stays fixed for the whole run.
function M.play(bufnr, win, on_done, opts)
  opts = opts or {}
  local message = opts.message or M.random_message()
  local total_frames = opts.total_frames or (M.frame_count() * 5)
  local interval_ms = opts.interval_ms or 150

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

  if vim.api.nvim_win_is_valid(win) then
    local skip_opts = { buffer = bufnr, silent = true, nowait = true }
    for _, key in ipairs(skip_keys) do
      vim.keymap.set("n", key, finish, skip_opts)
    end
  end

  local function step(index)
    if stopped or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if index > total_frames then
      finish()
      return
    end

    local ok = pcall(function()
      local lines, highlights = M.frame(index, message)
      vim.bo[bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.bo[bufnr].modifiable = false
      apply_highlights(bufnr, highlights)
    end)
    if not ok then
      finish()
      return
    end

    vim.defer_fn(function()
      step(index + 1)
    end, interval_ms)
  end

  step(1)
end

return M
