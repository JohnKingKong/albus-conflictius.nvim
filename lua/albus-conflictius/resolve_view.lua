local M = {}

local wand = require("albus-conflictius.wand")

local LABELS = { [1] = "base", [2] = "ours", [3] = "theirs" }

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

  if jump_to_first_hunk(bufnr, win) then
    local remaining = current_hunks(bufnr)
    vim.notify(
      string.format("albus-conflictius: %d conflict%s remaining", #remaining, #remaining == 1 and "" or "s"),
      vim.log.levels.INFO
    )
  else
    vim.notify("albus-conflictius: no conflict markers remain -- :w to save and stage", vim.log.levels.INFO)
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
  vim.keymap.set("n", "<leader>cd", function()
    if #handle.scratch_bufnrs > 0 then
      close_diff_panes()
    else
      open_diff_panes()
    end
  end, vim.tbl_extend("force", keymap_opts, { desc = "albus-conflictius: toggle base/ours/theirs diff view" }))

  jump_to_first_hunk(main_bufnr, main_win)

  vim.notify(
    "albus-conflictius: resolving "
      .. path
      .. " -- <leader>co/ct/cb accept ours/theirs/both, <leader>cn/cp next/prev conflict, <leader>cd full diff view",
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
