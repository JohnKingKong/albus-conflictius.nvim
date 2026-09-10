local M = {}

local wand = require("albus-conflictius.wand")

local NAMESPACE = vim.api.nvim_create_namespace("albus-conflictius-resolve-view")

-- `default = true` so these only apply when the colorscheme/user hasn't already defined them.
-- DiffDelete/DiffAdd (red/green) are the most universally distinct pair across colorschemes --
-- DiffChange varies too much (e.g. reads as a muddy near-green in some earthy themes).
vim.api.nvim_set_hl(0, "AlbusConflictiusOurs", { default = true, link = "DiffDelete" })
vim.api.nvim_set_hl(0, "AlbusConflictiusTheirs", { default = true, link = "DiffAdd" })

local function current_hunks(bufnr)
  return wand.parse_hunks(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
end

-- Background-highlights the "ours" and "theirs" sides of every remaining hunk so they're visually
-- distinct at a glance. Ours/theirs are always immediately after the opening `<<<<<<<` and
-- immediately before the closing `>>>>>>>` respectively, regardless of a diff3 base in between.
local function highlight_hunks(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  for _, hunk in ipairs(current_hunks(bufnr)) do
    local ours_start = hunk.start_idx + 1
    local ours_end = ours_start + #hunk.ours - 1
    local theirs_end = hunk.end_idx - 1
    local theirs_start = theirs_end - #hunk.theirs + 1

    for line = ours_start, ours_end do
      vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, line - 1, 0, {
        end_row = line,
        end_col = 0,
        hl_group = "AlbusConflictiusOurs",
        hl_eol = true,
      })
    end
    for line = theirs_start, theirs_end do
      vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, line - 1, 0, {
        end_row = line,
        end_col = 0,
        hl_group = "AlbusConflictiusTheirs",
        hl_eol = true,
      })
    end
  end
end

local function hunk_at_cursor(bufnr, win)
  local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
  for _, hunk in ipairs(current_hunks(bufnr)) do
    if cursor_line >= hunk.start_idx and cursor_line <= hunk.end_idx then
      return hunk
    end
  end
  return nil
end

-- Jumps to the first remaining conflict hunk in the buffer. Returns false (and does not move the
-- cursor) when none remain, so callers can tell "nothing left to jump to" apart from "jumped".
local function jump_to_first_hunk(bufnr, win)
  local hunks = current_hunks(bufnr)
  if #hunks == 0 then
    return false
  end
  vim.api.nvim_win_set_cursor(win, { hunks[1].start_idx, 0 })
  return true
end

local function jump_hunk(bufnr, win, direction)
  local hunks = current_hunks(bufnr)
  if #hunks == 0 then
    vim.notify("albus-conflictius: no conflict markers remain", vim.log.levels.INFO)
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
  if direction == "next" then
    for _, hunk in ipairs(hunks) do
      if hunk.start_idx > cursor_line then
        vim.api.nvim_win_set_cursor(win, { hunk.start_idx, 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(win, { hunks[1].start_idx, 0 })
  else
    for i = #hunks, 1, -1 do
      if hunks[i].start_idx < cursor_line then
        vim.api.nvim_win_set_cursor(win, { hunks[i].start_idx, 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(win, { hunks[#hunks].start_idx, 0 })
  end
end

local function notify_remaining(bufnr)
  local remaining = current_hunks(bufnr)
  if #remaining == 0 then
    vim.notify("albus-conflictius: no conflict markers remain -- :w to save and stage", vim.log.levels.INFO)
  else
    vim.notify(
      string.format("albus-conflictius: %d conflict%s remaining", #remaining, #remaining == 1 and "" or "s"),
      vim.log.levels.INFO
    )
  end
end

-- Builds the "if every remaining hunk were resolved to `side`" rendering of the buffer, plus a
-- parallel line->hunk-index array (false for lines outside any hunk) so a side pane's cursor
-- position can be resolved back to which hunk it belongs to.
local function build_side_view(main_lines, side)
  local hunks = wand.parse_hunks(main_lines)
  local lines, line_hunks = {}, {}
  local cursor = 1
  for hunk_index, hunk in ipairs(hunks) do
    for i = cursor, hunk.start_idx - 1 do
      table.insert(lines, main_lines[i])
      table.insert(line_hunks, false)
    end
    local content = side == "ours" and hunk.ours or hunk.theirs
    for _, l in ipairs(content) do
      table.insert(lines, l)
      table.insert(line_hunks, hunk_index)
    end
    cursor = hunk.end_idx + 1
  end
  for i = cursor, #main_lines do
    table.insert(lines, main_lines[i])
    table.insert(line_hunks, false)
  end
  return lines, line_hunks
end

local function set_scratch_content(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

-- Re-renders the ours/theirs side panes from the main buffer's current content. Safe to call
-- unconditionally after any edit to the main buffer -- a no-op when the panes aren't open.
local function refresh_diff_panes(handle)
  if not handle.diff_open then
    return
  end
  local main_lines = vim.api.nvim_buf_get_lines(handle.main_bufnr, 0, -1, false)
  local ours_lines, ours_line_hunks = build_side_view(main_lines, "ours")
  local theirs_lines, theirs_line_hunks = build_side_view(main_lines, "theirs")
  set_scratch_content(handle.ours_bufnr, ours_lines)
  set_scratch_content(handle.theirs_bufnr, theirs_lines)
  handle.ours_line_hunks = ours_line_hunks
  handle.theirs_line_hunks = theirs_line_hunks
end

local function accept_hunk_index(handle, hunk_index, side)
  local main_lines = vim.api.nvim_buf_get_lines(handle.main_bufnr, 0, -1, false)
  local hunks = wand.parse_hunks(main_lines)
  local hunk = hunks[hunk_index]
  if not hunk then
    return
  end

  local replacement = {}
  if side == "ours" or side == "both" then
    vim.list_extend(replacement, hunk.ours)
  end
  if side == "theirs" or side == "both" then
    vim.list_extend(replacement, hunk.theirs)
  end

  vim.api.nvim_buf_set_lines(handle.main_bufnr, hunk.start_idx - 1, hunk.end_idx, false, replacement)
  highlight_hunks(handle.main_bufnr)
  jump_to_first_hunk(handle.main_bufnr, handle.main_win)
  notify_remaining(handle.main_bufnr)
  refresh_diff_panes(handle)
end

-- Replaces the conflict hunk under the cursor (in the result/main pane) with "ours", "theirs",
-- or "both" (ours then theirs). Works on any hunk shape, diff3-base or plain.
local function accept_hunk(handle, choice)
  local hunk = hunk_at_cursor(handle.main_bufnr, handle.main_win)
  if not hunk then
    vim.notify("albus-conflictius: cursor is not inside a conflict hunk", vim.log.levels.WARN)
    return
  end
  for index, h in ipairs(current_hunks(handle.main_bufnr)) do
    if h.start_idx == hunk.start_idx then
      accept_hunk_index(handle, index, choice)
      return
    end
  end
end

-- Accepts the hunk under the cursor in a side pane (ours or theirs), determined purely by which
-- pane the cursor is in -- no separate "which side" choice needed.
local function accept_from_side(handle, side)
  local win = side == "ours" and handle.ours_win or handle.theirs_win
  local line_hunks = side == "ours" and handle.ours_line_hunks or handle.theirs_line_hunks
  local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
  local hunk_index = line_hunks and line_hunks[cursor_line]
  if not hunk_index then
    vim.notify("albus-conflictius: cursor is not inside a conflict hunk", vim.log.levels.WARN)
    return
  end
  accept_hunk_index(handle, hunk_index, side)
end

-- Runs the same auto-resolve algorithm as the dashboard's "wand" keymap, but directly on this
-- buffer's in-memory content rather than reading the file from disk.
local function wand_buffer(handle)
  local content = table.concat(vim.api.nvim_buf_get_lines(handle.main_bufnr, 0, -1, false), "\n")
  local new_content, resolved_count, remaining_count = wand.resolve_content(content)
  vim.api.nvim_buf_set_lines(handle.main_bufnr, 0, -1, false, vim.split(new_content, "\n", { plain = true }))

  highlight_hunks(handle.main_bufnr)
  jump_to_first_hunk(handle.main_bufnr, handle.main_win)
  refresh_diff_panes(handle)

  if resolved_count == 0 and remaining_count == 0 then
    vim.notify("albus-conflictius: no conflict markers found", vim.log.levels.INFO)
  elseif remaining_count == 0 then
    vim.notify(
      string.format(
        "albus-conflictius: fully resolved (%d hunk%s) -- :w to save and stage",
        resolved_count,
        resolved_count == 1 and "" or "s"
      ),
      vim.log.levels.INFO
    )
  else
    vim.notify(
      string.format("albus-conflictius: %d resolved, %d still need manual resolution", resolved_count, remaining_count),
      vim.log.levels.WARN
    )
  end
end

local function close_diff_panes(handle)
  vim.cmd("diffoff!")
  if handle.ours_bufnr and vim.api.nvim_buf_is_valid(handle.ours_bufnr) then
    vim.api.nvim_buf_delete(handle.ours_bufnr, { force = true })
  end
  if handle.theirs_bufnr and vim.api.nvim_buf_is_valid(handle.theirs_bufnr) then
    vim.api.nvim_buf_delete(handle.theirs_bufnr, { force = true })
  end
  handle.ours_bufnr, handle.ours_win = nil, nil
  handle.theirs_bufnr, handle.theirs_win = nil, nil
  handle.ours_line_hunks, handle.theirs_line_hunks = nil, nil
  handle.diff_open = false
  vim.api.nvim_set_current_win(handle.main_win)
end

-- q closes the diff panes if open (non-destructive -- <leader>cd reopens them any time); with the
-- panes already closed, it closes the whole view, confirming first only if conflicts remain.
local function quit(handle)
  if handle.diff_open then
    close_diff_panes(handle)
    return
  end

  local content = table.concat(vim.api.nvim_buf_get_lines(handle.main_bufnr, 0, -1, false), "\n")
  if wand.has_conflict_markers(content) then
    local choice =
      vim.fn.confirm("albus-conflictius: conflicts remain in " .. handle.path .. ". Close anyway?", "&Yes\n&No", 2)
    if choice ~= 1 then
      return
    end
  end

  vim.cmd("tabclose")
end

local function open_side_pane(handle, side, split_cmd)
  vim.api.nvim_set_current_win(handle.main_win)
  vim.cmd(split_cmd)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_buf_set_name(bufnr, "[" .. side .. "] " .. handle.path)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.cmd("diffthis")
  local win = vim.api.nvim_get_current_win()

  local keymap_opts = { buffer = bufnr, silent = true }
  vim.keymap.set("n", "<CR>", function()
    accept_from_side(handle, side)
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: accept this side (" .. side .. ")" }))
  vim.keymap.set("n", "<leader>cn", function()
    jump_hunk(handle.main_bufnr, handle.main_win, "next")
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: next conflict" }))
  vim.keymap.set("n", "<leader>cp", function()
    jump_hunk(handle.main_bufnr, handle.main_win, "prev")
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: previous conflict" }))
  vim.keymap.set("n", "q", function()
    quit(handle)
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: close diff panes, or the whole view" }))

  return bufnr, win
end

local function open_diff_panes(handle)
  vim.api.nvim_set_current_win(handle.main_win)
  vim.cmd("diffthis")

  handle.ours_bufnr, handle.ours_win = open_side_pane(handle, "ours", "leftabove vsplit")
  handle.theirs_bufnr, handle.theirs_win = open_side_pane(handle, "theirs", "rightbelow vsplit")
  handle.diff_open = true

  refresh_diff_panes(handle)
  vim.api.nvim_set_current_win(handle.main_win)
end

function M.open(cwd, path, opts)
  opts = opts or {}

  vim.cmd("tabnew")
  vim.cmd("edit " .. vim.fn.fnameescape(cwd .. "/" .. path))
  local main_bufnr = vim.api.nvim_get_current_buf()
  local main_win = vim.api.nvim_get_current_win()

  local handle = {
    main_win = main_win,
    main_bufnr = main_bufnr,
    path = path,
    diff_open = false,
  }

  local keymap_opts = { buffer = main_bufnr, silent = true }
  vim.keymap.set("n", "<leader>co", function()
    accept_hunk(handle, "ours")
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: accept ours" }))
  vim.keymap.set("n", "<leader>ct", function()
    accept_hunk(handle, "theirs")
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: accept theirs" }))
  vim.keymap.set("n", "<leader>cb", function()
    accept_hunk(handle, "both")
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: accept both" }))
  vim.keymap.set("n", "<leader>cn", function()
    jump_hunk(main_bufnr, main_win, "next")
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: next conflict" }))
  vim.keymap.set("n", "<leader>cp", function()
    jump_hunk(main_bufnr, main_win, "prev")
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: previous conflict" }))
  vim.keymap.set("n", "<leader>cw", function()
    wand_buffer(handle)
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: run the wand on this file" }))
  vim.keymap.set("n", "<leader>cd", function()
    if handle.diff_open then
      close_diff_panes(handle)
    else
      open_diff_panes(handle)
    end
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: toggle ours/result/theirs diff view" }))
  vim.keymap.set("n", "q", function()
    quit(handle)
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: close diff panes, or the whole view" }))

  highlight_hunks(main_bufnr)
  jump_to_first_hunk(main_bufnr, main_win)

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = main_bufnr,
    callback = function()
      highlight_hunks(main_bufnr)
      refresh_diff_panes(handle)
    end,
  })

  vim.notify(
    "albus-conflictius: resolving "
      .. path
      .. " -- <leader>co/ct/cb accept ours/theirs/both, <leader>cn/cp next/prev, "
      .. "<leader>cw wand this file, <leader>cd ours|result|theirs view, q close",
    vim.log.levels.INFO
  )

  if opts.on_resolved then
    vim.api.nvim_create_autocmd("BufWritePost", {
      buffer = main_bufnr,
      callback = function()
        local content = table.concat(vim.api.nvim_buf_get_lines(main_bufnr, 0, -1, false), "\n")
        if not wand.has_conflict_markers(content) then
          opts.on_resolved(path)
        end
      end,
    })
  end

  return handle
end

return M
