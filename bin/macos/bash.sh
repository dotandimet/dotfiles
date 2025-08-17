#!/usr/bin/env bash

# Set Homebrew's bash as default shell

BREW_BASH="$(brew --prefix)/bin/bash"
grep -Fq "$BREW_BASH" /etc/shells || echo "${BREW_BASH}" | sudo tee -a /etc/shells
[[ "$SHELL" == "$BREW_BASH" ]] || chsh -s "${BREW_BASH}"


