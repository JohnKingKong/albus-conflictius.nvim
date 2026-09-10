local M = {}

local LASER_WIDTH = 33

-- `default = true` so these only apply when the colorscheme/user hasn't already defined them --
-- unlike the ours/theirs hunk highlights, these are meant to be vividly colorful regardless of
-- colorscheme (it's fireworks, not a serious UI element), so they're explicit hex, not Diff* links.
local SPARK_HL = {
  "AlbusConflictiusSpark1",
  "AlbusConflictiusSpark2",
  "AlbusConflictiusSpark3",
  "AlbusConflictiusSpark4",
}
vim.api.nvim_set_hl(0, "AlbusConflictiusSpark1", { default = true, fg = "#ff5f5f" })
vim.api.nvim_set_hl(0, "AlbusConflictiusSpark2", { default = true, fg = "#ffd75f" })
vim.api.nvim_set_hl(0, "AlbusConflictiusSpark3", { default = true, fg = "#5fd7ff" })
vim.api.nvim_set_hl(0, "AlbusConflictiusSpark4", { default = true, fg = "#ff5fff" })
vim.api.nvim_set_hl(0, "AlbusConflictiusLaser", { default = true, fg = "#ff875f" })
vim.api.nvim_set_hl(0, "AlbusConflictiusBorder", { default = true, fg = "#d7af5f" })

local NAMESPACE = vim.api.nvim_create_namespace("albus-conflictius-celebrate")

local SPARKLE_PATTERNS = {
  { 5, 14, 24 },
  { 2, 11, 20, 29 },
  { 8, 17, 27 },
  { 4, 13, 22, 31 },
}
local SPARK_CHARS = { "*", ".", "'", "+" }

-- Returns the row text plus a list of {col (0-based), hl_group} marks for its special characters,
-- computed at construction time rather than by re-scanning the rendered text afterward.
local function sparkle_row(positions)
  local row = {}
  for i = 1, LASER_WIDTH do
    row[i] = " "
  end
  local marks = {}
  for i, pos in ipairs(positions) do
    local char_index = ((i - 1) % #SPARK_CHARS) + 1
    row[pos] = SPARK_CHARS[char_index]
    table.insert(marks, { col = pos - 1, hl_group = SPARK_HL[char_index] })
  end
  return table.concat(row), marks
end

local function laser_row(spark_pos)
  local row = {}
  for i = 1, LASER_WIDTH do
    row[i] = (i == 1 or i == LASER_WIDTH) and "|" or "-"
  end
  row[spark_pos] = "*"
  return table.concat(row), { { col = spark_pos - 1, hl_group = "AlbusConflictiusLaser" } }
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

-- Frames are generated, not hand-drawn: two sparkle rows cycle through a small set of scatter
-- patterns, and a "laser" row's spark ping-pongs left-right across the width, around a message
-- whose border alternates. `message` is fixed for the whole playback (chosen once by
-- `play`/`random_message`), not re-picked per frame. No wizard art here -- this plays inside the
-- dashboard's own window at its current size, not resized to fit anything bigger.
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

  local row1, marks1 = sparkle_row(SPARKLE_PATTERNS[((i - 1) % #SPARKLE_PATTERNS) + 1])
  push(row1, marks1)
  local row2, marks2 = sparkle_row(SPARKLE_PATTERNS[(i % #SPARKLE_PATTERNS) + 1])
  push(row2, marks2)
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
  local right_border_start = #border + 2 + #message + 2
  push(message_line, {
    { col = 0, hl_group = "AlbusConflictiusBorder", col_end = #border },
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
