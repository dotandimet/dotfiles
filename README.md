# Dotan's Dotfiles

This is a personal dotfiles repository for building a consistent development
environment across macOS, Linux, and cloud workspaces such as GitHub Codespaces
and Coder.

The repository uses symlink-based installation and manages shell, terminal,
editor, Git, and development tooling configuration from a single source of
truth.

## Goals

A core principle of this setup is using:

- Homebrew for macOS packages, GUI applications, fonts, and system-level tooling
- Mise for developer tools and language runtimes that should work consistently
  across macOS, Linux, containers, and cloud workspaces

### macOS

- Homebrew
- Modern Bash
- Bash as the default shell

### macOS and Linux

- Ripgrep
- FZF
- Tmux
- Neovim
- JQ
- Mise for managing Node.js, Python, Perl, and other tools

## Installation

### Install everything

```bash
./install.sh
```

This:

1. Creates symlinks for configuration files
2. Creates symlinks for custom scripts in `bin/`
3. Installs tooling
   - macOS: Homebrew packages and shell setup
   - All platforms: Mise and configured tools

The installation process is idempotent and suitable for containers and cloud workspaces.

### Update managed tools

```bash
mise install
```

### Install macOS packages

```bash
brew bundle install
```

### Test installation

```bash
./tests/docker_test_mac.sh
```

Runs the installation process in a Linux container to validate changes.

### Run the test suite

The repository includes automated tests in the `tests/` directory:

- `*.bats` files contain Bats test cases for shell scripts and configuration
- `docker_test_mac.sh` validates the installation flow in a containerized environment

Run all Bats tests with:

```bash
mise test
```

The `mise test` task is defined in `mise.toml` and executes:

```bash
bats tests/
```

## Repository Structure

### Configuration layout

The repository follows XDG-style conventions:

- Root dotfiles such as `.bashrc`, `.bash_profile`, `.vimrc`, and `.tmux.conf`
  are linked into `~/`
- `config/*/` directories are linked into `~/.config/`
- `bin/` scripts are linked into `~/.local/bin/`

### Neovim

The active editor configuration is based on LazyVim.

See [docs/neovim.md](docs/neovim.md) for details about the setup and customizations.

## Tooling

### Mise

Mise is the primary cross-platform tool manager and one of the central pieces
of this repository.

Managed tools include:

- Languages: Node.js, Python, Perl
- CLI tools: fd, fzf, ripgrep, tmux, neovim, starship, shellcheck, gh, claude,
  gemini-cli, usage, and others

Using Mise keeps installations in the user home directory, making the setup
portable across local machines, containers, and cloud environments.

### Shell

Highlights:

- Unlimited history with timestamps
- PATH prioritizes `~/.local/bin` and Mise shims
- FZF integration
- Starship prompt
- Project navigation helpers
- Convenience aliases for launching Neovim

### Tmux

Configured with:

- `C-a` prefix instead of `C-b`
- Tokyo Night Moon theme
- vi-tmux-navigator integration
- Large scrollback history
- RGB color support

### Terminal emulators

Configured terminal environments include:

- Ghostty (current primary terminal)
- WezTerm
- Kitty

Common characteristics:

- Nerd Font support (Comic Shanns Mono)
- Consistent dark themes
- True-color support

## Common Commands

### Neovim

```bash
lv      # Primary LazyVim configuration
```

### Navigation

```bash
p       # FZF-based project picker
```

### Git

```bash
git dump     # Browse and extract historical file versions
git lg       # Formatted git log
git changed  # Files changed in a commit
git wmail    # Switch repository to work email
```

### Custom scripts

#### git-dump

Interactive Git history browser powered by FZF.

Features:

- Browse commits affecting a file
- Extract historical versions of files
- Preview content directly from history

## Notes

- There are experimental and legacy configurations under `config/`.
- Current daily-driver tools are Ghostty, Tmux, and the LazyVim configuration
  in `config/lazyvim`.
- Because most configuration is symlinked, many changes apply immediately.
  Running `./install.sh` ensures new files and links are installed correctly.
