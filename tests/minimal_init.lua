local root = vim.fn.getcwd()
vim.opt.rtp:append(root)
vim.opt.rtp:append(root .. "/.deps/plenary.nvim")

vim.cmd("runtime! plugin/plenary.vim")
