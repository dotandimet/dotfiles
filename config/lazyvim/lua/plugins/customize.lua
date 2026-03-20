return {
  {
    "folke/tokyonight.nvim",
    name = "tokyonight",
    opts = {
      transparent = true,
      styles = {
        sidebars = "transparent",
        floats = "transparent",
      },
      on_highlights = function(hl, c)
        hl.LineNr = { fg = c.dark5 }
        hl.LineNrAbove = { fg = c.dark5 }
        hl.LineNrBelow = { fg = c.dark5 }
        hl.CursorLineNr = { fg = c.blue2, bold = true }
      end,
    },
  },
  {
    "rose-pine/neovim",
    name = "rose-pine",
    opts = {
      styles = {
        transparency = true,
      },
      -- visual selection is fixed in an autocmd
    },
  },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      transparent_background = true,
      float = {
        transparent = true,
      },
    },
  },
  -- add dracula
  { "Mofiqul/dracula.nvim", name = "dracula" },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "tokyonight-moon",
    },
  },
}
