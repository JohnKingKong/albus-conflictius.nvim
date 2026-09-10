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

function M.open(cwd, path, opts)
  opts = opts or {}
  local git = opts.git or require("albus-conflictius.git")

  vim.cmd("tabnew")
  vim.cmd("edit " .. vim.fn.fnameescape(cwd .. "/" .. path))
  local main_bufnr = vim.api.nvim_get_current_buf()
  local main_win = vim.api.nvim_get_current_win()
  vim.cmd("diffthis")

  local scratch_bufnrs = {}
  for stage = 1, 3 do
    local content = git.show(cwd, stage, path)
    table.insert(scratch_bufnrs, open_scratch(LABELS[stage], path, content))
  end

  vim.api.nvim_set_current_win(main_win)

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

  return { main_win = main_win, main_bufnr = main_bufnr, scratch_bufnrs = scratch_bufnrs }
end

return M
