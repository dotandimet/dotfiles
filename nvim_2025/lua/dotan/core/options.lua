vim.cmd("let g:netrw_liststyle = 3")

-- vim.opt.incsearch = true
vim.opt.autoindent = false
vim.opt.background = "dark"
vim.opt.conceallevel = 1 -- for obsidian plugin
vim.opt.cursorline = true
vim.opt.directory = "/tmp"
vim.opt.expandtab = true
vim.opt.fillchars = {
    foldopen = "",
    foldclose = "",
    fold = " ",
    foldsep = " ",
    diff = "╱",
    eob = " ",
}
vim.opt.foldcolumn = "auto"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 1
vim.opt.foldmethod = "expr"
vim.opt.hlsearch = false
vim.opt.ignorecase = true
vim.opt.list = true
vim.opt.listchars = { trail = ".", tab = ">.", conceal = "+" }
vim.opt.nu = true
vim.opt.relativenumber = true
vim.opt.scrolloff = 8
vim.opt.shiftwidth = 2
vim.opt.smartcase = true
vim.opt.smartindent = true
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.swapfile = false
vim.opt.tabstop = 2
vim.opt.termguicolors = true
vim.opt.hidden = true
