# AGENTS.md

Instructions for coding agents working in this repository.

## Key Rules

- This is a dotfiles repository managed through symlinks. Edit files in this repository, not files under `~/.config/` or other installed locations.
- When modifying Neovim configuration, clarify which setup is intended if it is not obvious:
  - `config/lazyvim` (primary)
  - `config/nvim_2025` (legacy)
  - `config/nvim-coc` (legacy)
- After changing configuration, recommend the relevant follow-up step when applicable:
  - Bash: `source ~/.bashrc`
  - Neovim plugins: `:Lazy sync`
  - Mise: `mise install`
- Prefer validating installation-related changes with `./tests/docker_test_mac.sh` when practical.
- Be aware that macOS uses Homebrew in addition to Mise, while Linux relies more heavily on Mise.
