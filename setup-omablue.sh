#!/bin/bash

# --- Configuration Variables ---
# The source repository for the omablue project
REPO_URL="https://github.com/your-username/omablue.git"
# Target directory for the local repository clone
TARGET_DIR="$HOME/.local/share/omablue"
# Path to the configuration files inside the cloned repo
CONFIG_SRC="$TARGET_DIR/config"
# Standard user configuration path
USER_CONFIG="$HOME/.config"

echo "🚀 Starting Omablue setup for Secureblue (Fedora Atomic)..."

# 1. Install Homebrew if not present (Recommended for Atomic systems)
if ! command -v brew &>/dev/null; then
  echo "🍺 Homebrew not found. Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to path for the current session
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# 2. Install TUI tools via Brew
echo "📦 Installing TUI tools and fonts via Brew..."
brew install btop lazygit gum neovim fastfetch font-hack-nerd-font

# 3. Clone the Omablue repository
if [ ! -d "$TARGET_DIR" ]; then
  echo "📥 Cloning repository into $TARGET_DIR..."
  mkdir -p "$TARGET_DIR"
  git clone "$REPO_URL" "$TARGET_DIR"
else
  echo "🔄 Repository exists. Pulling latest updates..."
  git -C "$TARGET_DIR" pull
fi

# 4. Backup existing configurations in ~/.config
echo "💾 Backing up existing configurations in $USER_CONFIG..."
# Iterate through folders present in the omablue config source
for folder in $(ls "$CONFIG_SRC"); do
  if [ -d "$USER_CONFIG/$folder" ]; then
    echo "⚠️  Backing up $folder to $folder.bakup"
    # Move existing config to .bakup to avoid conflicts
    mv "$USER_CONFIG/$folder" "$USER_CONFIG/$folder.bakup"
  fi
done

# 5. Deploy Omablue configurations
echo "📂 Copying new configurations to $USER_CONFIG..."
# Copy content from /config/ into ~/.config/
cp -r "$CONFIG_SRC/." "$USER_CONFIG/"

# 6. Secureblue specific: Ensure local binaries are executable
if [ -d "$HOME/bin" ]; then
  echo "🔒 Setting execution permissions for local scripts..."
  chmod +x "$HOME/bin/"*
fi

echo "✅ Setup complete!"
echo "💡 Pro-tip: Run 'ujust update' to ensure your secureblue base is current."
