#!/usr/bin/env bash

# Installation script for rsync-tool
# https://github.com/Maolipeng/rsync-tool

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
GITHUB_REPO="Maolipeng/rsync-tool"
SCRIPT_NAME="deploy.sh" # Script name in the repository
COMMAND_NAME="rsynctool"    # Desired command name after installation
REPO_BRANCH="main"          # Or "master" if that's your default branch

# Determine installation directory (prefer user-local bin)
INSTALL_DIR="$HOME/.local/bin"
DEST_PATH="$INSTALL_DIR/$COMMAND_NAME"

# --- Helper Functions ---
print_info() {
    echo "INFO: $1"
}

print_warning() {
    echo "WARN: $1" >&2
}

print_error() {
    echo "ERROR: $1" >&2
    exit 1
}

# --- Prerequisite Check ---
# Check for curl or wget
if command -v curl > /dev/null 2>&1; then
    DOWNLOAD_CMD="curl -fsSL" # Fail silently, show errors, follow redirects
elif command -v wget > /dev/null 2>&1; then
    DOWNLOAD_CMD="wget -qO-" # Quiet, output to stdout
else
    print_error "Neither curl nor wget found. Please install one of them."
fi

# --- Installation ---
print_info "Starting installation of $COMMAND_NAME..."

# Create installation directory if it doesn't exist
if [ ! -d "$INSTALL_DIR" ]; then
    print_info "Creating installation directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR" || print_error "Failed to create directory $INSTALL_DIR"
fi

# Check if the directory is writable
if [ ! -w "$INSTALL_DIR" ]; then
    print_error "Installation directory $INSTALL_DIR is not writable. Check permissions."
fi

# Construct the download URL for the raw script content
SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${REPO_BRANCH}/${SCRIPT_NAME}"

print_info "Downloading $SCRIPT_NAME from $SCRIPT_URL..."

# Download the script and save it to the destination path
if [[ "$DOWNLOAD_CMD" == "curl"* ]]; then
    $DOWNLOAD_CMD "$SCRIPT_URL" -o "$DEST_PATH"
else # wget
    $DOWNLOAD_CMD "$SCRIPT_URL" > "$DEST_PATH"
fi

# Check if download was successful (basic check: file exists and is not empty)
if [ ! -s "$DEST_PATH" ]; then
    print_error "Download failed or resulted in an empty file. Check URL and network connection."
fi

print_info "Setting execute permissions for $DEST_PATH..."
chmod +x "$DEST_PATH" || print_error "Failed to set execute permissions on $DEST_PATH"

print_info "$COMMAND_NAME installed successfully to $DEST_PATH"

# --- PATH Check ---
# Check if the installation directory is in the PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    print_warning "$INSTALL_DIR is not in your PATH."
    print_warning "You need to add it to your shell configuration file (e.g., ~/.bashrc, ~/.zshrc, ~/.profile)."
    echo ""
    print_warning "Add the following line to your shell profile:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
    print_warning "Then, reload your shell configuration by running:"
    echo "  source ~/.bashrc  # (or ~/.zshrc, ~/.profile, etc.)"
    print_warning "Or simply start a new terminal session."
else
    print_info "$INSTALL_DIR is already in your PATH."
fi

echo ""
print_info "Installation complete! You can now run the tool using the command: $COMMAND_NAME"

exit 0