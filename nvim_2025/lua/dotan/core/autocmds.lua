-- Set indentation to 2 spaces
local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd
augroup("setIndent", { clear = true })
autocmd("Filetype", {
    group = "setIndent",
    pattern = {
        "css",
        "html",
        "javascript",
        "lua",
        "markdown",
        "md",
        "typescript",
        "scss",
        "xml",
        "xhtml",
        "yaml",
    },
    command = "setlocal shiftwidth=2 tabstop=2",
})

