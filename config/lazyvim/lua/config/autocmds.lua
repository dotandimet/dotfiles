-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
--

-- Fix Visual selection highlight for transparent themes
vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "rose-pine*",
  callback = function()
    vim.api.nvim_set_hl(0, "Visual", { bg = "#6e6a86" })
  end,
})
