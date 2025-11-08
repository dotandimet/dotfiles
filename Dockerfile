# Use a recent Ubuntu image as the base
FROM ubuntu:latest

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install essential dependencies for the dotfiles
# This includes git, curl, build-essential for compiling, and sudo.
# 'file' is often useful for debugging.
RUN apt-get update && apt-get install -y     build-essential     curl     file     git     sudo     bash     && rm -rf /var/lib/apt/lists/*

# Create a non-root user 'developer' with sudo privileges
# and set a simple password ('password').
RUN useradd --create-home --shell /bin/bash developer &&     adduser developer sudo &&     echo "developer:password" | chpasswd

# Set the working directory to the user's home
WORKDIR /home/developer

# Copy the dotfiles from the build context into the container
COPY . .

# Change the ownership of the copied files to the new user
RUN chown -R developer:developer /home/developer

# Switch to the non-root user
USER developer

# Make the main installation script executable
RUN chmod +x install.sh

# Execute the installation script.
# You may need to inspect 'install.sh' to ensure it can run
# non-interactively. This basic command assumes it can.
RUN ./install.sh

# Set the default command to start a login shell.
# This will ensure that shell profiles like .bash_profile are loaded.
CMD ["/bin/bash", "-l"]


