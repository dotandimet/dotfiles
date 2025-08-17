# shellcheck shell=bash

export LC_ALL=en_US.UTF-8
export EDITOR=nvim
# History
export HISTSIZE=
export HISTFILESIZE=
export HISTTIMEFORMAT="[%F %T] "
export HISTFILE=~/.all_history
# append to history file instead of overwriting
shopt -s histappend
# A new shell gets the history lines from all previous shells
PROMPT_COMMAND='history -a'
# Don't put duplicate lines in the history.
export HISTCONTROL=ignoredups


function parse_git_dirty {
  [[ $(git status --porcelain 2>/dev/null) ]] && echo "*"
}

PROMPT_COMMAND='PS1_CMD1=$(git branch --show-current 2>/dev/null)'; PS1='\[\e[38;5;197m\]\u\[\e[0m\]@\[\e[38;5;37m\]\h\[\e[0m\] \[\e[38;5;45m\]\w\[\e[0m\] \[\e[38;5;40m\]${PS1_CMD1}\[\e[0m\] >'
# from https://bash-prompt-generator.org/

if [[ -n $(which vivid) ]]; then
  LS_COLORS=$(vivid generate molokai)
  export LS_COLORS
fi
# this silliness is useless unless we enable the --color option for ls:
alias ls="ls --color=auto"

alias lv="env NVIM_APPNAME=lazyvim nvim"
alias nv25="env NVIM_APPNAME=nvim_2025 nvim"
