#!/usr/bin/env bash

export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CONF_DIR=${1:-"${SCRIPT_DIR}"}

# Install software:
echo "Installing software"

if uname -a | grep -q Darwin; then
  echo "Installing macos stuff"
  "${SCRIPT_DIR}/bin/macos/brew.sh" # brew and software installed with brew
  "${SCRIPT_DIR}/bin/macos/bash.sh" # make homebrew bash login shell
fi

echo "Installing dotfiles from ${CONF_DIR}"

cd "${CONF_DIR}" || exit
for CONF in *; do
  SRC="${CONF_DIR}/${CONF}"
  TARGET=""
  if [[ "${CONF}" == $(basename "${BASH_SOURCE[0]}") ]]; then
    echo "$CONF is this script, skipping..."
  elif [[ "${CONF}" == "Brewfile" ]]; then
    echo "Skipping Brewfile..."
  elif [[ -d "${CONF}" ]]; then
    echo "${CONF} is a directory"
    TARGET="${HOME}/.config/${CONF}"
  else
    TARGET="${HOME}/.${CONF}"
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
    echo "Installing ${CONF}"
    ln -s "${SRC}" "${TARGET}" && echo "Installed link in ${TARGET}"
  fi
done
