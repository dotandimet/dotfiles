#!/usr/bin/env bash

brew install --adopt bash
BREW_BASH="$(brew --prefix)/bin/bash"
grep -Fq "$BREW_BASH" /etc/shells || echo "${BREW_BASH}" | sudo tee -a /etc/shells
[[ "$SHELL" == "$BREW_BASH" ]] || chsh -s "${BREW_BASH}"

brew install bash-completion@2

export BASH_COMPLETION_COMPAT_DIR="$(brew --prefix)/etc/bash_completion.d"

PROFILE="${CONF_DIR:-/tmp/dotfiles}/bash_profile"
[[ -e "${PROFILE}" ]] || mkdir -p $(dirname "${PROFILE}")

cat >> "${PROFILE}" <<EOT
# Add bash completion to ~/.bash_profile
export BASH_COMPLETION_COMPAT_DIR="${BASH_COMPLETION_COMPAT_DIR}"
[[ -r "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]] && . "$(brew --prefix)/etc/profile.d/bash_completion.sh"

EOT

