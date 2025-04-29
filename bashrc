# shellcheck shell=bash
# Ghostty shell integration for Bash. This should be at the top of your bashrc!
if [ -n "${GHOSTTY_RESOURCES_DIR}" ]; then
  builtin source "${GHOSTTY_RESOURCES_DIR}/shell-integration/bash/ghostty.bash"
fi

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

mail_warn() { echo ''; }

if hostname | grep -q platelet; then
  mail_warn() {
    mail=$(test -d .git && git config user.email)
    mail=${mail/dotan.dimet@cytoreason.com/}
    if [[ ! "$(test -d .git && git config user.email)" == *dotan.dimet@cytoreason.com* ]]; then
      echo " ${mail}"
    else
      echo ""
    fi
  }
fi

kube_config=""
get_kube_config() {
  kube_config=$(rg -i current-context ~/.kube/config | awk '{ print $NF }')
  if [[ -n "${kube_config}" ]]; then
    echo "${kube_config} "
  else
    echo ""
  fi
}

function parse_git_dirty {
  [[ $(git status --porcelain 2>/dev/null) ]] && echo "*"
}

function parse_git_branch {
  branch=$(test -d .git && git branch --show-current)
  if [[ -n "${branch}" ]]; then
    echo " ${branch}"
  else
    echo ""
  fi
}

export PS1="\[\033[38;5;221m\]\u\[\033[00m\]@\[\033[36m\]\h \[\033[35m\]\$(get_kube_config)\[\033[00m\]\w\[\033[32m\]\$(parse_git_branch)\[\033[33m\]\[\033[00m\]\[\033[38;5;196m\]\$(mail_warn)\[\033[00m\]>"

if [[ -n $(which vivid) ]]; then
  LS_COLORS=$(vivid generate molokai)
  export LS_COLORS
fi
# this silliness is useless unless we enable the --color option for ls:
alias ls="ls --color=auto"

alias kc="kubectl config get-contexts"
alias kctx='kube_config=$(kubectl config get-contexts -o=name | fzf ) && kubectl config use-context $kube_config'

if [[ -d "${HOME}/google-cloud-sdk" ]]; then
  export USE_GKE_GCLOUD_AUTH_PLUGIN=True
fi

alias excel='open -a "Microsoft Excel" '
alias lazyvim="env NVIM_APPNAME=lazyvim nvim"
