#!/usr/bin/env bash

brew --version >& /dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

PROFILE="${CONF_DIR:-/tmp/dotfiles}/bash_profile"
[[ -e "${PROFILE}" ]] || mkdir -p $(dirname "${PROFILE}")

cat >> "${PROFILE}" <<EOT
eval "$(/opt/homebrew/bin/brew shellenv)"
EOT
