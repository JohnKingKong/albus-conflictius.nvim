local M = {}

local ART = {
  "                             /\\",
  "                            /  \\",
  "                           |    |",
  "                         --:'''':--",
  "                           :'_' :",
  '                           _:"":\\___',
  "            ' '      ____.' :::     '._",
  "           . *=====<<=)           \\    :",
  "            .  '      '-'-'\\_      /'._.'",
  '                             \\====:_ ""',
  "                            .'     \\\\",
  "                           :       :",
  "                          /   :    \\",
  "                         :   .      '.",
  "         ,. _        snd :  : :      :",
  "      '-'    ).          :__:-:__.;--'",
  "    (        '  )        '-'   '-'",
  " ( -   .00.   - _",
  "(    .'  _ )     )",
  "'-  ()_.\\,\\,   -",
}

function M.art()
  return vim.deepcopy(ART)
end

function M.help_lines()
  local lines = M.art()
  table.insert(lines, "")
  table.insert(lines, "albus-conflictius.nvim — merge conflict manager")
  table.insert(lines, "")
  table.insert(lines, "Commands:")
  table.insert(lines, "  :AlbusConflictius       open the conflict dashboard")
  table.insert(lines, "  :AlbusConflictiusHelp   show this help")
  table.insert(lines, "")
  table.insert(lines, "Dashboard keymaps:")
  table.insert(lines, "  <CR>  open file under cursor")
  table.insert(lines, "  w     run the wand on the file under cursor")
  table.insert(lines, "  W     run the wand on every conflicted file")
  table.insert(lines, "  ?     show this help")
  table.insert(lines, "  q     close")
  table.insert(lines, "")
  table.insert(lines, "Resolve view keymaps (once a file is open):")
  table.insert(lines, "  <leader>co  accept ours for the hunk under the cursor")
  table.insert(lines, "  <leader>ct  accept theirs for the hunk under the cursor")
  table.insert(lines, "  <leader>cb  accept both (ours then theirs)")
  table.insert(lines, "  <leader>cn  jump to next conflict")
  table.insert(lines, "  <leader>cp  jump to previous conflict")
  table.insert(lines, "  <leader>cw  run the wand on this file (buffer, not disk)")
  table.insert(lines, "  <leader>cd  toggle the full base/ours/theirs diff view")
  table.insert(lines, "  q           close diff panes, or the whole view")
  table.insert(lines, "  :w          save -- auto-stages once no markers remain")
  return lines
end

function M.show_help()
  local lines = M.help_lines()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].bufhidden = "wipe"

  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
  end
  width = math.min(width + 2, math.floor(vim.o.columns * 0.8))
  local height = math.min(#lines, math.floor(vim.o.lines * 0.8))

  local win = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " albus-conflictius ",
  })

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = bufnr, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = bufnr, silent = true })

  return win
end

return M
