# Dotan's Dotfiles

Development configuration for macOS and unprivileged Linux environments,
including Codespaces and Coder. Mise installs tools and copies configuration
from this repository into your home directory.

## Install

Prerequisites: Bash, Git, curl, CA certificates, and mise **2026.9.13 or newer**
(or use `install.sh` below to install mise).

Review the repository before trusting it. From this checkout:

```bash
mise trust
mise bootstrap --dry-run
mise bootstrap
```

If mise is not installed, `./install.sh` installs it in `~/.local/bin`, trusts
this checkout, and forwards its arguments to `mise bootstrap`. This also
provides the conventional dotfiles entry point for Codespaces/Coder:

```bash
./install.sh --yes
```

Bootstrap installs tools and applies configuration. Back up any existing
configuration first. It does not change your login shell.

Configuration targets `~/.config`; a non-default `XDG_CONFIG_HOME` is not
supported.

### Platform tools

| Manifest                           | Purpose                                                   |
| ---------------------------------- | --------------------------------------------------------- |
| `mise/conf.d/dotfiles-common.toml` | Shared mise tools, language runtimes, settings            |
| `mise/conf.d/dotfiles-linux.toml`  | Prebuilt Neovim and tmux, installed by mise only on Linux |
| `mise/conf.d/dotfiles-macos.toml`  | macOS-only Homebrew formulae, Ghostty, and font           |

The fragments load automatically for the appropriate platform. Bootstrap
copies them into `~/.config/mise/conf.d/` so tools remain available outside the
checkout, without replacing a personal mise config.

On Apple Silicon macOS, mise installs Homebrew packages into `/opt/homebrew`
using its built-in package manager; a `brew` executable is not required.
Prefix creation and some app installs may request administrator permission.
Xcode Command Line Tools may be needed. Mise's built-in Homebrew backend does
not currently support Intel Macs; those packages must be installed separately.

Linux uses prebuilt releases installed under your home directory, without sudo
or system package installation. It requires a supported glibc-based host with
standard archive utilities and upstream runtime libraries (notably
`libatomic.so.1` for Node 26 on arm64). The host/image must provide these;
bootstrap does not install system libraries, a compiler toolchain, GUI apps,
or fonts.

## Everyday updates

Edit files **in the repository**, not the installed copies. From this checkout,
preview and apply your changes (or changes pulled from Git):

```bash
mise dot diff
mise dot apply
mise dot status --missing
```

**Add new files to Git before applying**: directory copies deploy only
Git-indexed files. Changes to already tracked files do not need a commit.

- After changing Bash configuration: `source ~/.bashrc`.
- After changing Neovim plugins: `:Lazy sync`.
- To apply configuration and install missing tools: `mise bootstrap`.
- For versioned tools only: `mise install`.
- For macOS packages only: `mise bootstrap --only packages`.

### How configuration is applied

- Most configuration becomes **regular copies**, not links. Scripts in `bin/`
  are copied to `~/.local/bin/` with their executable permissions preserved.
- `config/` maps to `~/.config/`, except the explicitly mapped home files:
  `config/_pi/` → `~/.pi/`, `config/_agents/` → `~/.agents/`, and the
  fenced files listed below.
- `.bashrc`, `.bash_profile`, `.inputrc`, and `~/.config/git/config` receive
  the corresponding tracked content inside `mise:dotfiles` comment fences.
  Mise updates that block and preserves text outside it.
- Unrelated destination files are preserved. Removing a source file or entry
  does **not** delete its previously installed copy; review and remove stale
  copies explicitly.

Sync is explicit and one-way: repo → installed files on each apply.
Whole-file copies overwrite local edits to the same file; back those up or
copy wanted changes into the repo first. Fenced blocks preserve bytes outside
their markers, but shell settings inside a block can still override earlier
settings when sourced.

Bootstrap requires real destination directories and rejects symlinks at
fenced-file targets. Back up any conflicting links and preserve their local
content in regular directories/files before installing.

This is a **public repository**. Keep credentials, sessions, caches, and other
runtime state in installed directories, not the checkout; untracked files are
not included in directory copies.

## Daily use

- `lv`: LazyVim Neovim configuration. See [Neovim notes](docs/neovim.md).
- `p`: FZF project picker.
- `np`: create a project and change into it.
- `git dump`: browse/extract historical file versions.
- `git lg`: formatted Git history.
- Tmux uses `C-a`, Tokyo Night Moon, and vi-tmux-navigator.

Agent configuration lives under `config/_pi/agent/` and
`config/_agents/`. Only reviewed configuration and skills are tracked.
`pi update --extensions` restores Pi packages from their settings declarations.
The Herdr integration extension is an imported snapshot managed by Herdr.

## Validate changes

```bash
mise test
./tests/docker_test_mac.sh
```

The Bats suite checks configuration deployment against isolated temporary homes
and Git indexes, without installing tools.

The container test requires Apple's `container` CLI on macOS. It snapshots the
**current worktree**, including uncommitted installer changes, and runs a full
bootstrap in Ubuntu as a user with **no sudo**. It verifies Neovim and tmux,
reapplies dotfiles, and runs tests. An optional GitHub token is passed as a
build secret, never baked into the image.
