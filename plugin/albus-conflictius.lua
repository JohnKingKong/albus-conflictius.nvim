if vim.g.loaded_albus_conflictius then
  return
end
vim.g.loaded_albus_conflictius = true

vim.api.nvim_create_user_command("AlbusConflictius", function()
  require("albus-conflictius").open()
end, {
  desc = "Open the merge conflict dashboard for the current repo",
})

vim.api.nvim_create_user_command("AlbusConflictiusHelp", function()
  require("albus-conflictius").help()
end, {
  desc = "Show albus-conflictius.nvim's wizard art and command reference",
})
