# AGENTS.md

Instructions for coding agents working in this repository.

## Key Rules

- **This is a public repository.** Never commit sensitive content: API keys,
  tokens, passwords, private hostnames, internal company names, customer data,
  or anything that should remain private. When writing examples in skills or
  documentation, use generic domain concepts (e.g., `Order`, `Product`) rather
  than real internal names.
- This is a dotfiles repository managed through symlinks. Edit files in this
  repository, not files under `~/.config/` or other installed locations.
- When modifying Neovim configuration, do so only under `config/lazyvim` unless
  explicitly asked to, other neovim cofig directories are either legacy or
  experimental.
- After changing configuration, recommend the relevant follow-up step when
  applicable:
  - Bash: `source ~/.bashrc`
  - Neovim plugins: `:Lazy sync`
  - Mise: `mise install`
- Prefer validating installation-related changes with
  `./tests/docker_test_mac.sh` when practical.
- Be aware that macOS uses Homebrew in addition to Mise, while Linux relies
  more heavily on Mise.
