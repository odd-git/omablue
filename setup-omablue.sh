#!/bin/bash

# --- Configuration Variables ---
# Public HTTPS URL ensures no credentials are required for end-users
REPO_URL="https://github.com/your-username/omablue.git"
TARGET_DIR="$HOME/.local/share/omablue"
CONFIG_SRC="$TARGET_DIR/config"
USER_CONFIG="$HOME/.config"

# Function to handle backups efficiently, optimized for Btrfs
backup_config() {
  local folder=$1
  local target="$USER_CONFIG/$folder"

  if [ -d "$target" ]; then
    echo "⚠️  Backing up existing config: $folder"
    # Use reflink on Btrfs to save space; otherwise perform a standard move
    if [[ "$(findmnt -n -o FSTYPE -T "$target")" == "btrfs" ]]; then
      cp -r --reflink=always "$target" "${target}_$(date +%Y%m%d_%H%M%S).bak"
    else
      mv "$target" "${target}_$(date +%Y%m%d_%H%M%S).bak"
    fi
  fi
}

echo "🚀 Starting Omablue setup for Secureblue (Fedora Atomic)..."

# 1. Initialize Directory Structure
# Ensure local share and config directories exist before proceeding
echo "📁 Initializing directory structures..."
mkdir -p "$TARGET_DIR"
mkdir -p "$USER_CONFIG"
mkdir -p "$HOME/bin"

# 2. Install Homebrew if not present (Non-interactive mode)
if ! command -v brew &>/dev/null; then
  echo "🍺 Homebrew not found. Installing Homebrew..."
  export NONINTERACTIVE=1
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to path for the current session
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# 3. Install TUI tools and fonts via Brew
echo "📦 Installing required TUI tools..."
# Installs btop, lazygit, gum, neovim, and nerd fonts
brew install btop lazygit gum neovim fastfetch font-hack-nerd-font

# 4. Clone or Update the Omablue repository
# GIT_TERMINAL_PROMPT=0 prevents hanging on credential prompts
if [ ! -d "$TARGET_DIR/.git" ]; then
  echo "📥 Cloning public repository: $REPO_URL"
  GIT_TERMINAL_PROMPT=0 git clone "$REPO_URL" "$TARGET_DIR"
else
  echo "🔄 Repository exists. Pulling latest updates..."
  GIT_TERMINAL_PROMPT=0 git -C "$TARGET_DIR" pull
fi

# 5. Deploy configurations with Btrfs-aware backup logic
echo "📂 Deploying configurations to $USER_CONFIG..."

# Safely iterate through directories in the source config folder
if [ -d "$CONFIG_SRC" ]; then
  find "$CONFIG_SRC" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | while read -r folder; do
    backup_config "$folder"
    # Deploy new configuration files
    cp -r "$CONFIG_SRC/$folder" "$USER_CONFIG/"
  done
else
  echo "❌ Error: Configuration source directory not found in the repository."
fi

# 6. Secureblue specific: Hardening local binary permissions
echo "🔒 Setting secure execution permissions for local scripts..."
# Restrict permissions to owner only (rwx------) for enhanced privacy
