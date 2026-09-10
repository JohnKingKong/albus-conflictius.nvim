local M = {}

local banner = require("albus-conflictius.banner")

local function render(bufnr, files, show_banner)
  local lines = {}
  local offset = 0
  if show_banner then
    lines = banner.art()
    local divider_width = 0
    for _, line in ipairs(lines) do
      divider_width = math.max(divider_width, #line)
    end
    table.insert(lines, "")
    table.insert(lines, string.rep("-", divider_width))
    table.insert(lines, "")
    offset = #lines
  end
  for _, path in ipairs(files) do
    table.insert(lines, path)
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  return offset
end

local function file_under_cursor(handle)
  local lnum = vim.api.nvim_win_get_cursor(handle.win)[1]
  local idx = lnum - handle.offset
  if idx < 1 or idx > #handle.files then
    return nil
  end
  return handle.files[idx]
end

function M.open(files, opts)
  opts = opts or {}

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].bufhidden = "wipe"

  local width = 40
  for _, path in ipairs(files) do
    width = math.max(width, #path + 2)
  end

  local art_line_count = 0
  if opts.show_banner then
    local art = banner.art()
    art_line_count = #art + 3 -- blank line + divider + blank line
    for _, line in ipairs(art) do
      width = math.max(width, #line + 2)
    end
  end

  width = math.min(width, math.floor(vim.o.columns * 0.8))
  local height = math.min(math.max(#files, 1) + art_line_count, math.floor(vim.o.lines * 0.8))

  local win = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " albus-conflictius: conflicted files ",
    zindex = 300,
  })

  vim.api.nvim_set_current_win(win)
  vim.cmd("stopinsert")

  local handle = { win = win, bufnr = bufnr, files = files, offset = 0 }
  handle.offset = render(bufnr, files, opts.show_banner)

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = bufnr, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = bufnr, silent = true })

  if opts.on_open then
    vim.keymap.set("n", "<CR>", function()
      local path = file_under_cursor(handle)
      if path then
        opts.on_open(path)
      end
    end, { buffer = bufnr, silent = true })
  end

  if opts.on_wand then
    vim.keymap.set("n", "w", function()
      local path = file_under_cursor(handle)
      if path then
        opts.on_wand(path)
      end
    end, { buffer = bufnr, silent = true })
  end

  if opts.on_wand_all then
    vim.keymap.set("n", "W", function()
      opts.on_wand_all()
    end, { buffer = bufnr, silent = true })
  end

  if opts.on_help then
    vim.keymap.set("n", "?", function()
      opts.on_help()
    end, { buffer = bufnr, silent = true })
  end

  return handle
end

function M.refresh(handle, files)
  if not vim.api.nvim_win_is_valid(handle.win) then
    return
  end
  if #files == 0 then
    M.close(handle)
    return
  end
  handle.files = files
  handle.offset = render(handle.bufnr, files, handle.offset > 0)
end

function M.close(handle)
  if vim.api.nvim_win_is_valid(handle.win) then
    vim.api.nvim_win_close(handle.win, true)
  end
end

return M
