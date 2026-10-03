# Build-time apt is only for the test image's base OS. The actual bootstrap
# runs as an unprivileged user with no sudo and no compiler toolchain.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl git libatomic1 locales tar gzip xz-utils unzip \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8

RUN useradd --create-home --shell /bin/bash developer
WORKDIR /home/developer/dotfiles

# The macOS test supplies a tar to preserve nested build-context files.
ARG DOTFILES_SOURCE=.
ADD --chown=developer:developer ${DOTFILES_SOURCE} .
USER developer
ENV PATH="/home/developer/.local/bin:${PATH}"

RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN \
    MISE_MINIMUM_RELEASE_AGE=0s ./install.sh --yes \
    && mise bootstrap --only dotfiles --yes \
    && mise dot status --missing \
    && mise exec -- nvim --version \
    && mise exec -- tmux -V \
    && mise run test

CMD ["/bin/bash", "-l"]
