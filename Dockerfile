# Build-time apt is only for the test image's base OS. Bootstrap runs as
# developer, with passwordless sudo for mise's login-shell setup and no compiler toolchain.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
  bash ca-certificates curl git libatomic1 locales sudo tar gzip xz-utils unzip \
  && rm -rf /var/lib/apt/lists/* \
  && locale-gen en_US.UTF-8

# Match mise's resolved bash path so chsh does not prompt for a password.
RUN useradd --create-home --shell /usr/bin/bash developer \
  && printf 'developer ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/developer \
  && chmod 0440 /etc/sudoers.d/developer \
  && visudo -cf /etc/sudoers.d/developer
WORKDIR /home/developer/dotfiles

# The macOS test supplies a tar to preserve nested build-context files.
ARG DOTFILES_SOURCE=.
ADD --chown=developer:developer ${DOTFILES_SOURCE} .
# WORKDIR creates the repository directory as root; ADD only owns its contents.
RUN chown -R developer:developer /home/developer/dotfiles
USER developer
ENV PATH="/home/developer/.local/bin:${PATH}"

RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN \
  git status --short \
  && MISE_MINIMUM_RELEASE_AGE=0s ./install.sh --yes \
  && mise bootstrap --only dotfiles --yes \
  && mise dot status --missing \
  && mise exec -- nvim --version \
  && mise exec -- tmux -V \
  && mise run test

CMD ["/bin/bash", "-l"]
