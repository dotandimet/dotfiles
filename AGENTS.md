# AGENTS.md

Instructions for coding agents working in this repository.

## Key Rules

- **This is a public repository.** Never commit sensitive content: API keys,
  tokens, passwords, private hostnames, internal company names, customer data,
  or anything that should remain private.
- Edit configuration in this repository, not installed copies under `~/.config/`
  or other home-directory locations. Do not bootstrap the real HOME to test changes.
- When modifying Neovim configuration, do so only under `config/lazyvim` unless
  explicitly asked to, other neovim cofig directories are either legacy or
  experimental.
- After changing configuration, recommend the relevant follow-up step when
  applicable:
  - Dotfiles: `mise dot apply` (from this checkout)
  - Bash: `mise dot apply`, then `source ~/.bashrc`
  - Neovim plugins: `:Lazy sync`
  - Mise: `mise install`
- Prefer validating installation-related changes with
  `./tests/docker_test_mac.sh` when practical.
- Linux bootstrap must remain unprivileged: do not add sudo/system-package
  installation or tools that require system build dependencies.
