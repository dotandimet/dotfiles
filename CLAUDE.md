# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a comprehensive dotfiles repository for managing development environment configurations across macOS and Linux. The repository uses symlink-based installation and manages configurations for shell, terminal emulators, Neovim, Tmux, Git, and development tools via Mise.

## Common Commands

### Installation & Setup

```bash
# Install all dotfiles (creates symlinks, installs tools)
./install.sh

# Test installation in Docker (Linux simulation)
./tests/docker_test_mac.sh

# Install/update all mise-managed tools
mise install

# Install macOS packages via Homebrew
brew bundle install
```

### Development Tools

```bash
# Launch different Neovim configurations
nv25          # Primary Neovim 2025 config (nvim_2025)
lv            # LazyVim starter config
nvim          # Default config (nvim-coc legacy)

# Project navigation
p             # FZF-based project directory picker (go_to_project function)

# Git utilities
git dump      # Interactive FZF-based git history browser/file extractor
git lg        # Pretty formatted git log
git changed   # Show files changed in a commit
git wmail     # Switch to work email for repo
```

## Architecture & Structure

### Configuration Organization

The repository follows XDG Base Directory standards:
- **Root dotfiles** (`.bashrc`, `.bash_profile`, `.vimrc`, `.tmux.conf`) symlink to `~/`
- **Config directories** (`config/*/`) symlink to `~/.config/`
- **Custom scripts** (`bin/`) symlink to `~/.local/bin/`

### Installation System (install.sh)

The installation script operates in three phases:

1. **Symlink configuration files**: Creates symlinks from repo to standard locations, backing up existing files with `_bak` suffix
2. **Symlink custom scripts**: Links scripts from `bin/` to `~/.local/bin/`
3. **Install tooling**:
   - **macOS**: Installs Homebrew, runs `brew bundle`, sets newer bash as default shell
   - **All platforms**: Installs Mise version manager, runs `mise install` for all tools

The installation is idempotent and non-interactive, suitable for containers and CI environments.

### Neovim Configuration (nvim_2025)

The primary Neovim configuration at `config/nvim_2025/` uses a modular architecture:

**Structure**:
- `init.lua` - Entry point
- `lua/dotan/lazy.lua` - Lazy.nvim bootstrap
- `lua/dotan/core/` - Core editor settings (options, keymaps, autocmds, filetypes)
- `lua/dotan/plugins/` - ~20 plugin specifications as individual Lua modules
- `lazy-lock.json` - Plugin version lock file

**Key integrations**:
- LSP via Mason (auto-installs: ts_ls, html, cssls, lua_ls, pyright)
- Formatting via Conform.nvim (Prettier, stylua, black, shfmt)
- Linting via nvim-lint (ESLint_d, Pylint, Vale, Shellcheck)
- UI via Snacks (comprehensive utilities), which-key, Lualine
- TreeSitter for syntax, Telescope for fuzzy finding, Oil for file navigation

**Keymap conventions**: Space leader with mnemonic prefixes (`<leader>f` = find, `<leader>m` = make, etc.)

### Version Management (Mise)

Mise (`config/mise/mise.toml`) manages 16 tools as "latest" versions:
- **Languages**: Node, Python, Perl
- **CLI tools**: fd, fzf, ripgrep, tmux, neovim, starship, shellcheck, gh, claude, gemini-cli, usage, etc.

Mise provides shims that automatically select the correct version. Tools are installed per-user, making them portable across systems without requiring sudo.

### Shell Configuration (bashrc)

Key patterns:
- Unlimited history with timestamps
- PATH management: `~/.local/bin` prioritized, then Mise shims
- Tool integrations: FZF (Ctrl-R history, Alt-C cd), Mise activation, Starship prompt
- Custom functions: `parse_git_dirty()` for git status, `go_to_project()` for project navigation
- Aliases for different Neovim configs

### Terminal Configurations

Three terminal emulators are configured:
- **Ghostty** (`config/ghostty/config`) - Tokyo Night Moon theme, Comic Shanns Mono font, 0.9 opacity, Alt-as-Alt on macOS
- **WezTerm** (`config/wezterm/`) - Lua-based with system-aware Rose Pine theming
- **Kitty** (`config/kitty/kitty.conf`) - Alternative terminal config

All use Comic Shanns Mono Nerd Font and maintain consistent dark themes.

### Tmux Configuration

Tmux (`config/tmux/tmux.conf`) is configured with:
- Prefix remapped from `C-b` to `C-a`
- Tokyo Night Moon color scheme
- Vi-tmux-navigator integration for seamless Neovim/Tmux pane navigation
- 99M line scrollback history
- RGB color support

### Multiple Neovim Setups

Three Neovim configurations are maintained:
- **nvim_2025** - Primary modern Lua config with Lazy.nvim (recommended)
- **lazyvim** - LazyVim starter template for testing/reference
- **nvim-coc** - Legacy VimScript config with CoC.nvim

When editing Neovim configs, clarify which setup the user is referring to.

### Custom Scripts

**git-dump** (`bin/git-dump`):
- Interactive utility using FZF for browsing git history
- Shows commits affecting a specific file
- Allows extracting historical file versions
- Integrates with FZF preview

## Important Notes

### When Modifying Configurations

- **Bashrc changes** require sourcing: `source ~/.bashrc`
- **Neovim plugin changes** require running `:Lazy sync` in Neovim
- **Mise tool changes** require running `mise install`
- **Symlinks**: Don't edit files in `~/.config/` directly - edit source files in this repo

### Testing Changes

Use Docker-based testing before deploying to primary system:
```bash
./tests/docker_test_mac.sh
```

This builds an Ubuntu container and tests the full installation process.

### Git Configuration

The git config includes work/personal email switching via `git wmail`. The bashrc includes `parse_git_dirty()` which checks if the current repo uses work vs. private email.

### Platform Differences

- **macOS**: Uses Homebrew for system packages, bash is upgraded to latest
- **Linux**: Relies more heavily on Mise for tool management
- Both platforms use identical config files via symlinks
