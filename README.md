# Dotan's Dotfiles

Just some dotfiles


## What I want on MacOS:

 * Brew
 * Newer bash
 * Make bash the default shell

## What I want on MacOS and Linux:

 * Ripgrep
 * FZF
 * Tmux
 * Neovim
 * JQ
 * asdf or mise, a version manager for node / python / perl etc.

Install these using brew or apt-get,
or just curl into .local from the github release?

The last solution is better if our home dir is on a persistent volume and we're running in a container.

## What I want in my config files:

### Terminal:

    * True Color term (ghostty, wezterm, whatever)
    * completions for all installed commands
    * prompt should show directory/username/host/git branch, maybe if it's dirty?
    * Other prompt stuff I have:
        * check if the git email in a repo is configured to private rather than work email
        * show what kubernetes cluster is selected 
      
