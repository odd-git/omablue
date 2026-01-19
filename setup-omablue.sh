#!/bin/bash

# --- Configuration Variables ---
# Use public HTTPS URL to ensure no credentials are required for end-users
REPO_URL="https://github.com/your-username/omablue.git"
TARGET_DIR="$HOME/.local/share/omablue"
CONFIG_SRC="$TARGET_DIR/config"
USER_CONFIG="$HOME/.config"

# Function to handle backups efficiently, especially on Btrfs filesystems
backup_config() {
  local folder=$1
  local target="$USER_CONFIG/$folder"

  if [ -d "$target" ]; then
    echo "⚠️  Backing up existing config: $folder"
    # If filesystem is Btrfs, use lightweight reflinks to save space
    if [[ "$(findmnt -n -o FSTYPE -T "$target")" == "btrfs" ]]; then
      cp -r --reflink=always "$target" "${target}_$(date +%Y%m%d_%H%M%S).bak"
    else
      mv "$target" "${target}_$(date +%Y%m%d_%H%M%S).bak"
    fi
  fi
}

echo "🚀 Starting Omablue setup for Secureblue (Fedora Atomic)..."

# 1. Install Homebrew if not present (Non-interactive mode)
if ! command -v brew &>/dev/null; then
  echo "🍺 Homebrew not found. Installing Homebrew..."
  export NONINTERACTIVE=1
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Load brew environment for the current session
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# 2. Install TUI tools and fonts via Brew
echo "📦 Installing required TUI tools..."
brew install btop lazygit gum neovim fastfetch font-hack-nerd-font

# 3. Clone or Update the Omablue repository
# Using GIT_TERMINAL_PROMPT=0 ensures the script fails immediately if there's an issue instead of hanging
if [ ! -d "$TARGET_DIR" ]; then
  echo "📥 Cloning public repository: $REPO_URL"
  mkdir -p "$TARGET_DIR"
  GIT_TERMINAL_PROMPT=0 git clone "$REPO_URL" "$TARGET_DIR"
else
  echo "🔄 Repository exists. Pulling latest updates..."
  GIT_TERMINAL_PROMPT=0 git -C "$TARGET_DIR" pull
fi

# 4. Deploy configurations with Btrfs-aware backup logic
echo "📂 Deploying configurations to $USER_CONFIG..."
mkdir -p "$USER_CONFIG"

# Iterate through directories in the source config folder safely
find "$CONFIG_SRC" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | while read -r folder; do
  backup_config "$folder"
  # Copy new configuration files
  cp -r "$CONFIG_SRC/$folder" "$USER_CONFIG/"
done

# 5. Secureblue specific: Hardening local binary permissions
if [ -d "$HOME/bin" ]; then
  echo "🔒 Setting secure execution permissions for local scripts..."
  # Restrict permissions to owner only (rwx------) for privacy and security
  find "$HOME/bin" -type f -exec chmod 700 {} +
fi

echo "✅ Setup complete!"
echo "💡 Pro-tip: Run 'ujust update' to ensure your secureblue base is current."
