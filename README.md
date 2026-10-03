# Dotan's Dotfiles

Development configuration for macOS and unprivileged Linux environments,
including Codespaces and Coder. **Mise bootstrap is the installer.**

## Install

Prerequisites: Bash, Git, curl, CA certificates, and mise **2026.9.13 or newer**.
Linux tools use prebuilt releases installed under your home directory; the
bootstrap does not use apt, sudo, Linuxbrew, or change your login shell.

From this checkout:

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

Review the repository before trusting it. Bootstrap changes installed
configuration; run it from the worktree you want to deploy, not concurrently
from multiple worktrees.

**Existing symlink installation?** Follow the migration steps below first.

The current native mise dotfile manifest targets `~/.config`. A non-default
`XDG_CONFIG_HOME` is rejected before writing: this mise version does not expand
environment variables or templates in dotfile target paths.

### Platform tools

| Manifest | Purpose |
| --- | --- |
| `mise/conf.d/dotfiles-common.toml` | Shared mise tools, language runtimes, settings |
| `mise/conf.d/dotfiles-linux.toml` | Prebuilt Neovim and tmux, installed by mise only on Linux |
| `mise/conf.d/dotfiles-macos.toml` | macOS-only Homebrew formulae, Ghostty, and font |

The fragments load automatically; no `-E` flag is needed. Explicit OS selectors
prevent macOS packages from running on Linux. Bootstrap copies these fragments
into `~/.config/mise/conf.d/` so tools remain available outside the checkout,
without replacing a personal mise config.

On Apple Silicon macOS, mise installs Homebrew packages into `/opt/homebrew`
using its built-in package manager; a `brew` executable is not required.
Prefix creation and some app installs may request administrator permission.
Xcode Command Line Tools may be needed. Mise's built-in Homebrew backend does
not currently support Intel Macs; those packages must be installed separately.
Bootstrap no longer runs `chsh` or modifies `/etc/shells`. Choose a login shell
separately if desired.

Linux deliberately does not install GUI applications or fonts. It assumes a
supported glibc-based Linux host with standard archive utilities and the
runtime libraries required by upstream binaries (notably `libatomic.so.1` for
Node 26 on arm64). Those must be supplied by the host/image; bootstrap does not
provision system libraries or a compiler toolchain.

## Sync configuration

Edit files **in the repository**, then preview and apply:

```bash
mise dot diff
mise dot apply
mise dot status --missing
source ~/.bashrc
```

Or run `mise bootstrap` again to apply configuration and install missing tools.
Use `mise install` for versioned tools only, and `mise bootstrap --only packages`
for macOS packages. After changing Neovim plugins, run `:Lazy sync`.

### Ownership rules

- Most configuration and `bin/` scripts become **regular copies**, not links.
  Copies preserve script executable permissions.
- `config/` maps to `~/.config/`, except the explicitly mapped home files:
  `config/_pi/` → `~/.pi/`, `config/_agents/` → `~/.agents/`, and the
  fenced files listed below.
- `.bashrc`, `.bash_profile`, `.inputrc`, and `~/.config/git/config` receive
  the corresponding tracked content inside `mise:dotfiles` comment fences.
  Mise updates that block and preserves text outside it.
- Directory copies use `manifest = "git"`: only Git-indexed files are deployed.
  **Add new files to Git before applying.** Ignored/untracked credentials,
  sessions, caches, and other runtime state are never deployed.
- Unrelated destination files are preserved. Removing a source file or entry
  does **not** delete its previously installed copy; review and remove stale
  copies explicitly.

Sync is explicit and one-way: repo → installed files on each apply.
Whole-file copies overwrite local edits to the same file; back those up or
copy wanted changes into the repo first. Fenced blocks preserve bytes outside
their markers, but shell settings inside a block can still override earlier
settings when sourced.

There is no watcher, background Git push, or automatic two-way sync. This is a
**public repository**: do not enable broad tracking/history sharing of home
directories, agent state, credentials, or environment-specific customizations.
Runtime data belongs in installed directories, not the source checkout.

## Migrate from symlinks

Back up your installed configuration first. Bootstrap's preflight rejects
directory symlinks and symlinks at fenced-file targets before deploying files.
It does not use force or silently follow them into the checkout.

1. For each fenced-file symlink (`.bashrc`, `.bash_profile`, `.inputrc`,
   `~/.config/git/config`), move the link to an **unused backup path**. For
   example, after checking `~/.bashrc.pre-mise` does not exist:

   ```bash
   mv ~/.bashrc ~/.bashrc.pre-mise
   ```

   If that file was entirely managed by the old repo, leave its destination
   absent; bootstrap creates the fenced version. If it contains personal
   customizations, restore **only those customizations** to a regular file
   before applying. Copying the entire old tracked content back would leave
   duplicate, unmanaged settings outside the new block.

2. For old directory links, replace the link with a real directory while
   preserving installed state. Example, using an unused backup name:

   ```bash
   mv ~/.pi ~/.pi.pre-mise
   mkdir ~/.pi
   cp -RL ~/.pi.pre-mise/. ~/.pi/
   ```

   Repeat for any linked configuration directories the preflight reports,
   including nested ones. Keep credentials and sessions locally; do not add
   them to this repository. Inspect dangling links before recursively copying.

3. Back up/remove the old installer-owned mise config link at
   `~/.config/mise/mise.toml`, if present. Do not remove an unrelated personal
   config. The replacement uses namespaced `conf.d/dotfiles-*.toml` files.

4. Run `mise bootstrap --only dotfiles`, inspect `mise dot diff`, then run
   `mise bootstrap`. Existing leaf symlinks for whole-file copy entries are
   replaced with regular copies without modifying their old source.

## Validate changes

```bash
mise test
./tests/docker_test_mac.sh
```

The Bats suite runs native mise against isolated temporary homes and Git
indexes. It checks copies, fenced edits, repeat applies, preserved runtime
state, and safe rejection of legacy links. It does not install tools.

The macOS container test uses Apple's `container` CLI and snapshots the
**current worktree**, including uncommitted installer changes. It builds an
Ubuntu image, runs a full bootstrap as a user with **no sudo**, verifies Neovim
and tmux, reapplies dotfiles, and runs tests. A GitHub token is optional and is
passed as a build secret when available, never baked into the image.

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
