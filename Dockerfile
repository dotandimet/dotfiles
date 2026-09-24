# Use a recent Ubuntu image as the base
FROM ubuntu:latest

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install essential dependencies for the dotfiles
# This includes git, curl, build-essential for compiling, and sudo.
# 'file' is often useful for debugging.
# bison and curses are or installing tmux with mise, which builds it from source.
RUN apt-get update && apt-get install -y \
  build-essential \
  curl \
  file \
  git \
  sudo \
  bash  \
  bison libncurses-dev \
  locales \
  && rm -rf /var/lib/apt/lists/*

# Generate locate to avoid errors in some scripts
RUN locale-gen en_US.UTF-8 \
  && update-locale LANG=en_US.UTF-8

# Create a non-root user 'developer' with sudo privileges
# and set a simple password ('password').
RUN useradd --create-home --shell /bin/bash developer &&     adduser developer sudo &&     echo "developer:password" | chpasswd

# Set the working directory to the user's home
WORKDIR /home/developer

# Normally copy the checkout; the macOS test supplies a tar archive to work
# around container CLI versions that omit nested build-context files.
ARG DOTFILES_SOURCE=.
ADD ${DOTFILES_SOURCE} .

# Change the ownership of the copied files to the new user
RUN chown -R developer:developer /home/developer

# Switch to the non-root user
USER developer

# Make the main installation script executable
# and execute it
RUN chmod +x install.sh && env MISE_MINIMUM_RELEASE_AGE=0s ./install.sh

# Set the default command to start a login shell.
# This will ensure that shell profiles like .bash_profile are loaded.
CMD ["/bin/bash", "-l"]


