# shellcheck shell=bash
eval "$(/opt/homebrew/bin/brew shellenv)"

. "$(brew --prefix asdf)/libexec/asdf.sh"
. "$(brew --prefix asdf)/etc/bash_completion.d/asdf"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/dotan/google-cloud-sdk/path.bash.inc' ]; then . '/Users/dotan/google-cloud-sdk/path.bash.inc'; fi

# The next line enables shell command completion for gcloud.

if [ -f '/Users/dotan/google-cloud-sdk/completion.bash.inc' ]; then . '/Users/dotan/google-cloud-sdk/completion.bash.inc'; fi

# bash completions
export BASH_COMPLETION_COMPAT_DIR="/opt/homebrew/etc/bash_completion.d"
[[ -r "/opt/homebrew/etc/profile.d/bash_completion.sh" ]] && . "/opt/homebrew/etc/profile.d/bash_completion.sh"

# bash completion for git on mac:
# shellcheck source=/Library/Developer/CommandLineTools/usr/share/git-core/git-completion.bash
. "$(xcode-select -p)/usr/share/git-core/git-completion.bash"

# fzf should be in the homebrew path
# ---------

# Auto-completion
# ---------------
[[ $- == *i* ]] && source "/opt/homebrew/opt/fzf/shell/completion.bash" 2> /dev/null

# Key bindings
# ------------
source "/opt/homebrew/opt/fzf/shell/key-bindings.bash"

# AWS completions:
# https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-completion.html
if [[ -f /usr/local/bin/aws_completer ]]
then
    complete -C '/usr/local/bin/aws_completer' aws
fi

# DONE? Go!
[[ -r "${HOME}/.bashrc" ]] && . "${HOME}/.bashrc"

