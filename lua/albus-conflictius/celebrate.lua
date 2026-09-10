local M = {}

local banner = require("albus-conflictius.banner")

local LASER_WIDTH = 33

-- These are meant to be vividly colorful regardless of colorscheme (it's fireworks, not a
-- serious UI element), so they're explicit hex, not Diff*/colorscheme-derived links. `:colorscheme`
-- typically clears ALL highlight groups before applying its own, which would silently wipe these
-- out if we only ever set them once at module load -- so they're (re)applied on every ColorScheme
-- event too, not just at startup.
local SPARK_HL = {
  "AlbusConflictiusSpark1",
  "AlbusConflictiusSpark2",
  "AlbusConflictiusSpark3",
  "AlbusConflictiusSpark4",
  "AlbusConflictiusSpark5",
  "AlbusConflictiusSpark6",
}
local SPARK_COLORS = { "#ff5f5f", "#ffd75f", "#5fd7ff", "#ff5fff", "#5fff5f", "#af87ff" }

local function apply_colors()
  for idx, group in ipairs(SPARK_HL) do
    vim.api.nvim_set_hl(0, group, { fg = SPARK_COLORS[idx] })
  end
  vim.api.nvim_set_hl(0, "AlbusConflictiusBorder", { fg = "#d7af5f" })
end

apply_colors()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("albus-conflictius-celebrate-colors", { clear = true }),
  callback = apply_colors,
  desc = "albus-conflictius: re-apply celebration colors after a colorscheme change clears them",
})

local NAMESPACE = vim.api.nvim_create_namespace("albus-conflictius-celebrate")

-- Both sparkle rows are equally dense and span (nearly) the full laser width edge-to-edge --
-- two "full lines of stars", not a dense one over a sparse one -- differing only in exact
-- position/phase so they still read as two distinct rows rather than duplicates.
local SPARKLE_PATTERNS = {
  { 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32 },
  { 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31 },
  { 2, 5, 8, 11, 14, 17, 20, 23, 26, 29, 32 },
  { 3, 6, 9, 12, 15, 18, 21, 24, 27, 30 },
}
local SPARK_CHARS = { "*", ".", "'", "+", "x", "o" }

local WIZARD_ART = banner.art()
local WIZARD_WIDTH = 0
for _, line in ipairs(WIZARD_ART) do
  WIZARD_WIDTH = math.max(WIZARD_WIDTH, #line)
end

-- Centers `width` against `canvas_width`, the widest row in the *current* frame -- not a fixed
-- constant. The message line (border + text + border) can easily be wider than the wizard art,
-- and treating wizard width as the fixed reference clamped its padding to zero whenever that
-- happened, leaving the message flush-left while every other row stayed padded. Computing the
-- canvas width fresh per frame (as the max of wizard/laser/message widths) and centering every
-- row -- including the wizard art itself -- against that keeps them all aligned regardless of
-- which one happens to be widest.
local function pad_for(canvas_width, width)
  return string.rep(" ", math.max(0, math.floor((canvas_width - width) / 2)))
end

-- Returns the row text (centered against canvas_width) plus a list of {col (0-based), hl_group}
-- marks for its special characters, computed at construction time rather than by re-scanning the
-- rendered text afterward.
local function sparkle_row(positions, canvas_width)
  local row = {}
  for i = 1, LASER_WIDTH do
    row[i] = " "
  end
  local marks = {}
  local pad = pad_for(canvas_width, LASER_WIDTH)
  for i, pos in ipairs(positions) do
    local char_index = ((i - 1) % #SPARK_CHARS) + 1
    row[pos] = SPARK_CHARS[char_index]
    table.insert(marks, { col = #pad + pos - 1, hl_group = SPARK_HL[char_index] })
  end
  return pad .. table.concat(row), marks
end

-- The moving spark cycles through the same rainbow palette as the sparkle rows (keyed by frame
-- index) instead of a single fixed color, so it visibly flashes different colors as it sweeps.
local function laser_row(spark_pos, color_index, canvas_width)
  local row = {}
  for i = 1, LASER_WIDTH do
    row[i] = (i == 1 or i == LASER_WIDTH) and "|" or "-"
  end
  row[spark_pos] = "*"
  local pad = pad_for(canvas_width, LASER_WIDTH)
  local hl_group = SPARK_HL[((color_index - 1) % #SPARK_HL) + 1]
  return pad .. table.concat(row), { { col = #pad + spark_pos - 1, hl_group = hl_group } }
end

-- One mark per non-space character, cycling through the rainbow palette -- a proper multicolor
-- message instead of a single flat color.
local function rainbow_marks(text, start_col)
  local marks = {}
  for idx = 1, #text do
    if text:sub(idx, idx) ~= " " then
      table.insert(marks, {
        col = start_col + idx - 1,
        hl_group = SPARK_HL[((idx - 1) % #SPARK_HL) + 1],
      })
    end
  end
  return marks
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

-- Frames are generated, not hand-drawn: two equally dense sparkle rows spanning (almost) the
-- full laser width cycle through scatter patterns, and a "laser" row's spark ping-pongs
-- left-right while flashing through the rainbow palette, around a message whose text is itself
-- multicolor letter-by-letter. The canvas width is whichever row is widest *this frame* (the
-- message varies in length; the wizard/laser don't), and every row -- including the wizard art
-- itself -- is centered against that shared width. `message` is fixed for the whole playback
-- (chosen once by `play`/`random_message`), not re-picked per frame. This plays inside the
-- dashboard's own window at its current size, never resized to fit anything.
-- Returns (lines, highlights) -- highlights is a list of {row, col, hl_group} (0-based, single
-- character wide) plus border ranges, applied by `play` as extmarks.
function M.frame(index, message)
  message = message or M.MESSAGES[1]
  local i = ((index - 1) % M.frame_count()) + 1

  local border = (i % 2 == 0) and "*~*~*~*~*~*" or "~*~*~*~*~*~"
  local message_line = border .. "  " .. message .. "  " .. border

  local canvas_width = math.max(WIZARD_WIDTH, LASER_WIDTH, #message_line)

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

  local top, top_marks = sparkle_row(SPARKLE_PATTERNS[((i - 1) % #SPARKLE_PATTERNS) + 1], canvas_width)
  push(top, top_marks)
  local bottom, bottom_marks = sparkle_row(SPARKLE_PATTERNS[(i % #SPARKLE_PATTERNS) + 1], canvas_width)
  push(bottom, bottom_marks)
  push("")

  local wizard_pad = pad_for(canvas_width, WIZARD_WIDTH)
  for _, line in ipairs(WIZARD_ART) do
    push(wizard_pad .. line)
  end

  push("")

  local span = LASER_WIDTH - 2
  local cycle = 2 * span
  local pos = (i - 1) % cycle
  if pos >= span then
    pos = cycle - pos
  end
  local laser_line, laser_marks = laser_row(pos + 2, i, canvas_width)
  push(laser_line, laser_marks)
  push("")

  local pad = pad_for(canvas_width, #message_line)
  local message_start = #pad + #border + 2
  local right_border_start = message_start + #message + 2

  local message_marks = rainbow_marks(message, message_start)
  table.insert(message_marks, { col = #pad, hl_group = "AlbusConflictiusBorder", col_end = #pad + #border })
  table.insert(
    message_marks,
    { col = right_border_start, hl_group = "AlbusConflictiusBorder", col_end = right_border_start + #border }
  )
  push(pad .. message_line, message_marks)

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

-- Vertically centers `lines`/`highlights` within `window_height` by padding blank lines above
-- (and, if there's room, below) rather than leaving the animation stuck at the top of a taller
-- window. Never resizes anything -- purely a padding calculation over what's already there.
local function center_vertically(lines, highlights, window_height)
  local vpad = math.max(0, math.floor((window_height - #lines) / 2))
  if vpad == 0 then
    return lines, highlights
  end

  local padded = {}
  for _ = 1, vpad do
    table.insert(padded, "")
  end
  for _, line in ipairs(lines) do
    table.insert(padded, line)
  end

  local shifted = {}
  for _, h in ipairs(highlights) do
    table.insert(shifted, { row = h.row + vpad, col = h.col, col_end = h.col_end, hl_group = h.hl_group })
  end

  return padded, shifted
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
  local window_height = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_height(win) or 0

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
      lines, highlights = center_vertically(lines, highlights, window_height)
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
