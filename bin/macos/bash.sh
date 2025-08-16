#!/usr/bin/env bash

brew install --adopt bash
BREW_BASH="$(brew --prefix)/bin/bash"
grep -Fq "$BREW_BASH" /etc/shells || echo "${BREW_BASH}" | sudo tee -a /etc/shells
[[ "$SHELL" == "$BREW_BASH" ]] || chsh -s "${BREW_BASH}"

brew install bash-completion@2


