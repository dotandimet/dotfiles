#!/usr/bin/env bash

brew install bash
echo "$(brew --prefix)/bin/bash" | sudo tee -a /etc/shells
chsh -s "$(brew --prefix)/bin/bash"

brew install bash-completion@2

export BASH_COMPLETION_COMPAT_DIR="$(brew --prefix)/etc/bash_completion.d"

PROFILE="${CONF_DIR:-/tmp/dotfiles}/bash_profile"
[[ -e "${PROFILE}" ]] || mkdir -p $(dirname "${PROFILE}")

cat >> "${PROFILE}" <<EOT
# Add bash completion to ~/.bash_profile
export BASH_COMPLETION_COMPAT_DIR="${BASH_COMPLETION_COMPAT_DIR}"
[[ -r "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]] && . "$(brew --prefix)/etc/profile.d/bash_completion.sh"

EOT

