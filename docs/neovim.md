# Neovim Configuration

The active daily-driver Neovim setup is based on LazyVim and lives under `config/lazyvim`.

The repository may contain additional legacy or experimental editor configurations, but they are not considered maintained or documented.
## LazyVim Customizations

The primary Neovim setup is based on upstream LazyVim with a small number of local customizations.

### Themes

Default colorscheme:

- Tokyo Night Moon

Installed and customized themes include:

- Tokyo Night
- Rose Pine
- Catppuccin
- Dracula
- Nord
- Darcula
- Alabaster

Theme customizations focus primarily on transparent backgrounds and improved line-number visibility.

### Statusline

A custom lualine component displays a warning when a non-English keyboard layout is active.

This integrates with the local `check-keyboard-layout` script and is cached to avoid performance issues.

### Tmux Integration

Pane navigation is provided by `vim-tmux-navigator`.

Supported keybindings:

- Ctrl+h
- Ctrl+j
- Ctrl+k
- Ctrl+l

These work across both Neovim and tmux panes.

### Disabled Plugins

- `flash.nvim`

## Philosophy

Most editor behavior intentionally comes from upstream LazyVim defaults.

The goal is to minimize maintenance burden while keeping a small set of personal workflow customizations.