local M = {}

local banner = require("albus-conflictius.banner")

local DEFAULT_WIDTH = 40

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
end

apply_colors()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("albus-conflictius-celebrate-colors", { clear = true }),
  callback = apply_colors,
  desc = "albus-conflictius: re-apply celebration colors after a colorscheme change clears them",
})

local NAMESPACE = vim.api.nvim_create_namespace("albus-conflictius-celebrate")

local SPARK_CHARS = { "*", ".", "'", "+", "x", "o" }

local WIZARD_ART = banner.art()

-- A solid, edge-to-edge row of sparkle characters spanning the full given width -- no gaps, no
-- centering needed since it already fills the whole line. `phase` shifts which character (and
-- color) lands on each column, so two calls with different phases still read as visually distinct
-- rows despite both being fully dense. Returns the row text plus a list of {col (0-based),
-- hl_group} marks, computed at construction time rather than by re-scanning the text afterward.
local function sparkle_row(width, phase)
  local row = {}
  local marks = {}
  for pos = 1, width do
    local char_index = ((pos + phase - 1) % #SPARK_CHARS) + 1
    row[pos] = SPARK_CHARS[char_index]
    table.insert(marks, { col = pos - 1, hl_group = SPARK_HL[((pos + phase - 1) % #SPARK_HL) + 1] })
  end
  return table.concat(row), marks
end

-- The moving spark cycles through the same rainbow palette as the sparkle rows (keyed by frame
-- index) instead of a single fixed color, so it visibly flashes different colors as it sweeps.
-- Spans the full given width, edge-to-edge (`|` caps), same as every other row in this banner.
local function laser_row(width, spark_pos, color_index)
  local row = {}
  for i = 1, width do
    row[i] = (i == 1 or i == width) and "|" or "-"
  end
  spark_pos = math.min(math.max(spark_pos, 1), width)
  row[spark_pos] = "*"
  local hl_group = SPARK_HL[((color_index - 1) % #SPARK_HL) + 1]
  return table.concat(row), { { col = spark_pos - 1, hl_group = hl_group } }
end

-- A full-width alternating "*~*~*~" bar -- the bottom bookend of the laser/message/star-line
-- banner, matching the laser row's width exactly so the whole group reads as a uniform block.
local function star_line_row(width, phase)
  local chars = { "*", "~" }
  local row = {}
  local marks = {}
  for pos = 1, width do
    local char_index = ((pos + phase) % 2) + 1
    row[pos] = chars[char_index]
    table.insert(marks, { col = pos - 1, hl_group = SPARK_HL[((pos + phase - 1) % #SPARK_HL) + 1] })
  end
  return table.concat(row), marks
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

local function center_pad(width, content_width)
  return string.rep(" ", math.max(0, math.floor((width - content_width) / 2)))
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

-- Frames are generated, not hand-drawn. Two solid sparkle rows sit above the (static) wizard art,
-- pasted in as-is at its own hand-authored position (its shape depends on each line's own leading
-- whitespace, so it's never centered/padded like the rest of the frame). Below the wizard is a
-- tight three-row banner -- a laser row whose spark ping-pongs left-right, the message (plain,
-- centered, multicolor letter-by-letter), and a star-line bar -- all three spanning exactly
-- `width` (the real width of the window this plays in), so the message can never get clipped by
-- being wider than a fixed internal constant. `message` is fixed for the whole playback (chosen
-- once by `play`/`random_message`), not re-picked per frame. `width` defaults to a fixed constant
-- only for standalone calls (e.g. tests) made without a real window.
-- Returns (lines, highlights) -- highlights is a list of {row, col, hl_group} (0-based, single
-- character wide), applied by `play` as extmarks.
function M.frame(index, message, width)
  message = message or M.MESSAGES[1]
  width = width or DEFAULT_WIDTH
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

  local top, top_marks = sparkle_row(width, i)
  push(top, top_marks)
  local bottom, bottom_marks = sparkle_row(width, i + 3)
  push(bottom, bottom_marks)
  push("")

  for _, line in ipairs(WIZARD_ART) do
    push(line)
  end

  push("")

  local span = math.max(1, width - 2)
  local cycle = math.max(2, 2 * span)
  local pos = (i - 1) % cycle
  if pos >= span then
    pos = cycle - pos
  end
  local laser_line, laser_marks = laser_row(width, pos + 2, i)
  push(laser_line, laser_marks)

  local pad = center_pad(width, #message)
  local message_marks = rainbow_marks(message, #pad)
  push(pad .. message, message_marks)

  local star_line, star_marks = star_line_row(width, i)
  push(star_line, star_marks)

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
-- `opts.message` for tests) and stays fixed for the whole run. The banner rows are sized to the
-- window's actual width (read once at playback start) so the message is never clipped.
function M.play(bufnr, win, on_done, opts)
  opts = opts or {}
  local message = opts.message or M.random_message()
  local total_frames = opts.total_frames or (M.frame_count() * 5)
  local interval_ms = opts.interval_ms or 150
  local window_valid = vim.api.nvim_win_is_valid(win)
  local window_height = window_valid and vim.api.nvim_win_get_height(win) or 0
  local window_width = window_valid and vim.api.nvim_win_get_width(win) or DEFAULT_WIDTH

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

  if window_valid then
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
      local lines, highlights = M.frame(index, message, window_width)
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
