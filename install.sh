#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR=${1:-"${SCRIPT_DIR}/config"} # configs are in ./config, can be overwritten by first argument to script
TARGET_DIR=${XDG_CONFIG_HOME:-"${HOME}/.config"}
[[ -d "${TARGET_DIR}" ]] || mkdir -p "${TARGET_DIR}"

# Install software:
echo "Installing software"

if uname -a | grep -q Darwin; then
  echo "Installing macos stuff"
  "${SCRIPT_DIR}/bin/macos.sh"
fi

if [[ -x ~/.local/bin/mise ]]; then
  echo "mise package manager installed"
else
  curl https://mise.run | sh
fi

echo "Installing dotfiles from ${CONF_DIR}"

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

echo "Installing mise software..."
eval "$(~/.local/bin/mise activate bash --shims)" # so any shims added are available in the installlation
~/.local/bin/mise install
echo "DONE"
