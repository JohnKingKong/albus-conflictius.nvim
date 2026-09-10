local M = {}

local wand = require("albus-conflictius.wand")

local LABELS = { [1] = "base", [2] = "ours", [3] = "theirs" }

local NAMESPACE = vim.api.nvim_create_namespace("albus-conflictius-resolve-view")

-- `default = true` so these only apply when the colorscheme/user hasn't already defined them.
vim.api.nvim_set_hl(0, "AlbusConflictiusOurs", { default = true, link = "DiffChange" })
vim.api.nvim_set_hl(0, "AlbusConflictiusTheirs", { default = true, link = "DiffAdd" })

local function open_scratch(label, path, content)
  vim.cmd("vsplit")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_buf_set_name(bufnr, "[" .. label .. "] " .. path)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content or "", "\n", { plain = true }))
  vim.bo[bufnr].modifiable = false
  vim.cmd("diffthis")
  return bufnr
end

local function current_hunks(bufnr)
  return wand.parse_hunks(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
end

-- Background-highlights the "ours" and "theirs" sides of every remaining hunk so they're visually
-- distinct at a glance, without needing to read which marker means what. Ours/theirs are always
-- immediately after the opening `<<<<<<<` and immediately before the closing `>>>>>>>`
-- respectively, regardless of whether a diff3 base section is present in between.
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

-- Replaces the conflict hunk under the cursor with "ours", "theirs", or "both" (ours then
-- theirs), then jumps to the next remaining hunk (or reports none left). Works on any hunk
-- shape, diff3-base or plain — unlike the wand, this never needs a base to act.
local function accept_hunk(bufnr, win, choice)
  local hunk = hunk_at_cursor(bufnr, win)
  if not hunk then
    vim.notify("albus-conflictius: cursor is not inside a conflict hunk", vim.log.levels.WARN)
    return
  end

  local replacement = {}
  if choice == "ours" or choice == "both" then
    vim.list_extend(replacement, hunk.ours)
  end
  if choice == "theirs" or choice == "both" then
    vim.list_extend(replacement, hunk.theirs)
  end

  vim.api.nvim_buf_set_lines(bufnr, hunk.start_idx - 1, hunk.end_idx, false, replacement)
  highlight_hunks(bufnr)
  jump_to_first_hunk(bufnr, win)
  notify_remaining(bufnr)
end

-- Runs the same auto-resolve algorithm as the dashboard's "wand" keymap, but directly on this
-- buffer's in-memory content rather than reading the file from disk — so it picks up whatever
-- you've already edited here instead of risking clobbering it.
local function wand_buffer(bufnr, win)
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  local new_content, resolved_count, remaining_count = wand.resolve_content(content)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(new_content, "\n", { plain = true }))

  highlight_hunks(bufnr)
  jump_to_first_hunk(bufnr, win)

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

function M.open(cwd, path, opts)
  opts = opts or {}
  local git = opts.git or require("albus-conflictius.git")

  vim.cmd("tabnew")
  vim.cmd("edit " .. vim.fn.fnameescape(cwd .. "/" .. path))
  local main_bufnr = vim.api.nvim_get_current_buf()
  local main_win = vim.api.nvim_get_current_win()

  local handle = { main_win = main_win, main_bufnr = main_bufnr, scratch_bufnrs = {} }

  local function open_diff_panes()
    vim.api.nvim_set_current_win(main_win)
    vim.cmd("diffthis")
    for stage = 1, 3 do
      local content = git.show(cwd, stage, path)
      table.insert(handle.scratch_bufnrs, open_scratch(LABELS[stage], path, content))
    end
    vim.api.nvim_set_current_win(main_win)
  end

  local function close_diff_panes()
    vim.cmd("diffoff!")
    for _, bufnr in ipairs(handle.scratch_bufnrs) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    handle.scratch_bufnrs = {}
    vim.api.nvim_set_current_win(main_win)
  end

  local keymap_opts = { buffer = main_bufnr, silent = true }
  vim.keymap.set("n", "<leader>co", function()
    accept_hunk(main_bufnr, main_win, "ours")
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: accept ours" }))
  vim.keymap.set("n", "<leader>ct", function()
    accept_hunk(main_bufnr, main_win, "theirs")
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: accept theirs" }))
  vim.keymap.set("n", "<leader>cb", function()
    accept_hunk(main_bufnr, main_win, "both")
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: accept both" }))
  vim.keymap.set("n", "<leader>cn", function()
    jump_hunk(main_bufnr, main_win, "next")
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: next conflict" }))
  vim.keymap.set("n", "<leader>cp", function()
    jump_hunk(main_bufnr, main_win, "prev")
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: previous conflict" }))
  vim.keymap.set("n", "<leader>cw", function()
    wand_buffer(main_bufnr, main_win)
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: run the wand on this file" }))
  vim.keymap.set("n", "<leader>cd", function()
    if #handle.scratch_bufnrs > 0 then
      close_diff_panes()
    else
      open_diff_panes()
    end
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: toggle base/ours/theirs diff view" }))
  -- q closes the diff panes if they're open (returning to the single-pane view), otherwise
  -- closes the whole resolve view -- one key, no need to remember :tabclose or :diffoff.
  vim.keymap.set("n", "q", function()
    if #handle.scratch_bufnrs > 0 then
      close_diff_panes()
    else
      vim.cmd("tabclose")
    end
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: close diff panes, or the whole view" }))

  highlight_hunks(main_bufnr)
  jump_to_first_hunk(main_bufnr, main_win)

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = main_bufnr,
    callback = function()
      highlight_hunks(main_bufnr)
    end,
  })

  vim.notify(
    "albus-conflictius: resolving "
      .. path
      .. " -- <leader>co/ct/cb accept ours/theirs/both, <leader>cn/cp next/prev, "
      .. "<leader>cw wand this file, <leader>cd full diff view, q close",
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
