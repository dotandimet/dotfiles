#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR=${1:-"${SCRIPT_DIR}/config"} # configs are in ./config, can be overwritten by first argument to script
TARGET_DIR=${XDG_CONFIG_HOME:-"${HOME}/.config"}
[[ -d "${TARGET_DIR}" ]] || mkdir -p "${TARGET_DIR}"

# install brew, brew software listed in the Brewfile,
# and set bash as the default shell
function install_macos_stuff() {
  # brew and software installed with brew
  if [[ ! -x /opt/homebrew/bin/brew ]]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  eval "$(/opt/homebrew/bin/brew shellenv)"
  brew bundle install --file=Brewfile

  # Set Homebrew's bash as default shell
  BREW_BASH="$(brew --prefix)/bin/bash"
  grep -Fq "$BREW_BASH" /etc/shells || echo "${BREW_BASH}" | sudo tee -a /etc/shells
  [[ "$SHELL" == "$BREW_BASH" ]] || chsh -s "${BREW_BASH}"
}

# Install symlinks for config files
function symlink_config_files {
  cd "${CONF_DIR}" || exit
  for CONF in *; do
    SRC="${CONF_DIR}/${CONF}"
    TARGET=""
    if [[ "${CONF}" == "bashrc" ||
      "${CONF}" == "bash_profile" ||
      "${CONF}" == "inputrc" ||
      "${CONF}" == "vimrc" ||
      "${CONF}" == "tmux.conf" ]] \
      ; then
      TARGET="${HOME}/.${CONF}"
    else
      TARGET="${TARGET_DIR}/${CONF}"
    fi
    if [[ -L "${TARGET}" ]]; then
      if [[ "$(readlink "${TARGET}")" != "${SRC}" ]]; then
        echo "${TARGET} is a symlink but not to ${SRC}, moving to ${TARGET}_bak"
        mv "${TARGET}" "${TARGET}_bak"
      fi
    elif [[ -r "${TARGET}" ]]; then
      echo "${TARGET} exists but not a link, moving to ${TARGET}_bak"
      mv "${TARGET}" "${TARGET}_bak"
    fi
    # so now, $TARGET shouldn't exist unless it's Cool:
    if [[ -n "${TARGET}" && ! -e "${TARGET}" ]]; then
      echo "Installing ${CONF} configuration"
      ln -s "${SRC}" "${TARGET}" && echo "Installed link in ${TARGET}"
    fi
  done
}

# Install config files
echo "Installing dotfiles from ${CONF_DIR}"
symlink_config_files

# Install software:
echo "Installing software"

if uname -a | grep -q Darwin; then
  echo "Installing macos stuff"
  install_macos_stuff
fi

if [[ -x ~/.local/bin/mise ]]; then
  echo "mise package manager installed"
else
  curl https://mise.run | sh
fi

echo "Installing mise software..."
eval "$(~/.local/bin/mise activate bash --shims)" # so any shims added are available in the installlation
~/.local/bin/mise install
echo "DONE"
