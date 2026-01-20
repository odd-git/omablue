##!/bin/bash

# --- Secureblue Sway Architect: Omablue Setup Script ---
# Description: Installs omablue environment on secureblue Sericea
# Principles: Atomic-safe, Keyboard-driven, Brew-reliant, Fully Automated

REPO_URL="https://github.com/odd-git/omablue.git"
TEMP_DIR=$(mktemp -d)
OMABLUE_SHARE="$HOME/.local/share/omablue"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)

# Function for notifications
send_notification() {
  local status=$1
  local message=$2
  if [ "$status" == "success" ]; then
    notify-send -u normal -a "Omablue Setup" "Success" "$message" -h string:x-dunst-stack-tag:setup
  else
    notify-send -u critical -a "Omablue Setup" "Error" "$message" -h string:x-dunst-stack-tag:setup
  fi
}

# Function to safely add PATH to shell config
configure_shell_path() {
  local shell_rc="$1"
  local bin_path="$OMABLUE_SHARE/bin"

  if [ -f "$shell_rc" ]; then
    # Check if the path is already mentioned to avoid duplicates (Idempotency)
    if ! grep -q "$bin_path" "$shell_rc"; then
      echo "Configuring PATH in $shell_rc..."
      {
        echo ""
        echo "# --- Omablue Environment ---"
        echo "export PATH=\"$bin_path:\$PATH\""
      } >>"$shell_rc"
      echo "Updated $shell_rc."
    else
      echo "Path already present in $shell_rc. Skipping."
    fi
  fi
}

echo "Starting Omablue installation..."

# 1. Create necessary directory structure
mkdir -p "$OMABLUE_SHARE"

# 2. Clone the repository
if git clone "$REPO_URL" "$TEMP_DIR"; then
  echo "Repository cloned successfully."
else
  send_notification "error" "Failed to clone repository. Check your internet connection."
  exit 1
fi

# 3. Handle Backups of existing configs
echo "Backing up existing configurations..."
mkdir -p "$HOME/.config_backup_$BACKUP_DATE"

for folder in "$TEMP_DIR/config"/*; do
  folder_name=$(basename "$folder")
  if [ -d "$HOME/.config/$folder_name" ]; then
    mv "$HOME/.config/$folder_name" "$HOME/.config_backup_$BACKUP_DATE/"
  fi
done

# 4. Deploy Omablue files
echo "Deploying bin and config files..."

# Move bin folder to local share
if [ -d "$TEMP_DIR/bin" ]; then
  cp -r "$TEMP_DIR/bin" "$OMABLUE_SHARE/"
else
  send_notification "error" "Bin folder not found in repository."
  exit 1
fi

# Move config contents to ~/.config
cp -r "$TEMP_DIR/config"/* "$HOME/.config/"

# 5. Install dependencies via Homebrew
echo "Installing gum via Homebrew..."
if command -v brew &>/dev/null; then
  brew install gum
else
  echo "Homebrew not found. Please ensure Homebrew is installed first."
  send_notification "error" "Homebrew is missing. Install it to complete the setup."
  exit 1
fi

# 6. Automate Shell Path Configuration
echo "Configuring shell environment..."
configure_shell_path "$HOME/.bashrc"
configure_shell_path "$HOME/.zshrc"

# 7. Final Notification
send_notification "success" "Omablue setup complete. Please restart your shell or log out/in."

# Cleanup
rm -rf "$TEMP_DIR"

echo "Setup finished successfully."
