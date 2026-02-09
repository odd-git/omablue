#!/bin/bash

# --- Omablue Setup Installer ---
# Interactive installer for Secureblue Sericea Sway configuration
# Uses gum for beautiful terminal UI

set -e

# --- Configuration ---
REPO_URL="https://github.com/odd-git/omablue.git"
OMABLUE_SHARE="$HOME/.local/share/omablue"
OMABLUE_CONFIG="$HOME/.config/omablue"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
TEMP_DIR=""

# --- Colors (fallback if gum unavailable) ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Helper Functions ---
cleanup() {
  [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

error_exit() {
  echo -e "${RED}Error: $1${NC}" >&2
  notify-send -u critical "Omablue Setup" "Error: $1" 2>/dev/null || true
  exit 1
}

success_msg() {
  if command -v gum &>/dev/null; then
    gum style --foreground 42 "$1"
  else
    echo -e "${GREEN}$1${NC}"
  fi
}

info_msg() {
  if command -v gum &>/dev/null; then
    gum style --foreground 33 "$1"
  else
    echo -e "${BLUE}$1${NC}"
  fi
}

warn_msg() {
  if command -v gum &>/dev/null; then
    gum style --foreground 214 "$1"
  else
    echo -e "${YELLOW}$1${NC}"
  fi
}

# --- Pre-flight Checks ---
preflight_checks() {
  local missing=()

  # Check for git
  if ! command -v git &>/dev/null; then
    missing+=("git")
  fi

  # Check for homebrew (needed for gum/fzf)
  if ! command -v brew &>/dev/null; then
    if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    elif [[ -x /var/home/linuxbrew/.linuxbrew/bin/brew ]]; then
      eval "$(/var/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    else
      missing+=("homebrew")
    fi
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}Missing required dependencies: ${missing[*]}${NC}"
    echo ""
    echo "Please install the missing dependencies first:"
    [[ " ${missing[*]} " =~ " homebrew " ]] && echo "  Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    [[ " ${missing[*]} " =~ " git " ]] && echo "  Git: Usually pre-installed, or install via your package manager"
    exit 1
  fi

  # Install gum if not present (needed for interactive UI)
  if ! command -v gum &>/dev/null; then
    echo "Installing gum for interactive UI..."
    brew install gum || error_exit "Failed to install gum"
  fi
}

# --- Welcome Banner ---
show_welcome() {
  clear
  gum style \
    --border double \
    --border-foreground 99 \
    --padding "1 3" \
    --margin "1" \
    --align center \
    "$(gum style --foreground 99 --bold 'OMABLUE')" \
    "" \
    "$(gum style --foreground 245 'Secureblue Sway Configuration')" \
    "$(gum style --foreground 245 'Keyboard-driven • Atomic-safe • Beautiful')"

  echo ""
}

# --- User Confirmation ---
confirm_install() {
  gum style --foreground 245 "This installer will:"
  echo ""
  echo "  • Clone the Omablue repository"
  echo "  • Backup existing configs (sway, waybar, rofi, dunst, foot)"
  echo "  • Deploy scripts to ~/.local/share/omablue/"
  echo "  • Deploy configs to ~/.config/"
  echo "  • Install dependencies (gum, fzf)"
  echo "  • Set catppuccin as the default theme"
  echo ""

  if ! gum confirm "Proceed with installation?"; then
    echo ""
    gum style --foreground 214 "Installation cancelled."
    exit 0
  fi
}

# --- Directory Setup ---
setup_directories() {
  gum spin --spinner dot --title "Creating directories..." -- sleep 0.5

  mkdir -p "$OMABLUE_SHARE"
  mkdir -p "$OMABLUE_CONFIG/current"
  mkdir -p "$HOME/.config"
  mkdir -p "$HOME/.local/bin"

  success_msg "Directories created"
}

# --- Clone Repository ---
clone_repo() {
  TEMP_DIR=$(mktemp -d)

  gum spin --spinner dot --title "Cloning repository..." -- \
    git clone --depth 1 "$REPO_URL" "$TEMP_DIR"

  if [[ ! -d "$TEMP_DIR/bin" ]]; then
    error_exit "Repository structure invalid - missing bin folder"
  fi

  success_msg "Repository cloned"
}

# --- Backup Existing Configs ---
backup_configs() {
  local backup_dir="$HOME/.config_backup_$BACKUP_DATE"
  local backed_up=()

  # List of configs we'll be replacing
  local configs=(sway waybar rofi dunst foot ghostty)

  for folder in "${configs[@]}"; do
    if [[ -d "$HOME/.config/$folder" ]]; then
      backed_up+=("$folder")
    fi
  done

  if [[ ${#backed_up[@]} -gt 0 ]]; then
    info_msg "Backing up: ${backed_up[*]}"
    mkdir -p "$backup_dir"

    for folder in "${backed_up[@]}"; do
      gum spin --spinner dot --title "Backing up $folder..." -- \
        cp -r "$HOME/.config/$folder" "$backup_dir/"
    done

    success_msg "Backups saved to $backup_dir"
  else
    info_msg "No existing configs to backup"
  fi
}

# --- Deploy Files ---
deploy_files() {
  # Deploy bin scripts
  gum spin --spinner dot --title "Deploying scripts..." -- \
    cp -r "$TEMP_DIR/bin" "$OMABLUE_SHARE/"

  # Make scripts executable
  chmod +x "$OMABLUE_SHARE/bin/"*

  # Deploy themes
  if [[ -d "$TEMP_DIR/themes" ]]; then
    gum spin --spinner dot --title "Deploying themes..." -- \
      cp -r "$TEMP_DIR/themes" "$OMABLUE_SHARE/"
    success_msg "Themes deployed ($(ls -1 "$OMABLUE_SHARE/themes" | wc -l) themes)"
  fi

  # Deploy assets
  if [[ -d "$TEMP_DIR/assets" ]]; then
    gum spin --spinner dot --title "Deploying assets..." -- \
      cp -r "$TEMP_DIR/assets" "$OMABLUE_SHARE/"
    success_msg "Assets deployed"
  fi

  # Deploy config files
  if [[ -d "$TEMP_DIR/config" ]]; then
    gum spin --spinner dot --title "Deploying configs..." -- \
      cp -r "$TEMP_DIR/config"/* "$HOME/.config/"
    success_msg "Configs deployed"
  fi

  success_msg "All files deployed"
}

# --- Set Default Theme ---
set_default_theme() {
  local default_theme="catppuccin"
  local theme_path="$OMABLUE_SHARE/themes/$default_theme"

  if [[ -d "$theme_path" ]]; then
    gum spin --spinner dot --title "Setting default theme..." -- sleep 0.3

    # Create theme symlink
    ln -nsf "$theme_path" "$OMABLUE_CONFIG/current/theme"

    # Save theme name
    echo "$default_theme" > "$OMABLUE_CONFIG/current/theme.name"

    # Deploy default foot theme as bootstrap
    if [[ -f "$HOME/.config/foot/catppuccin-theme.ini" ]]; then
      cp "$HOME/.config/foot/catppuccin-theme.ini" "$OMABLUE_CONFIG/current/foot-theme.ini"
    fi

    # Generate initial theme files if generator exists
    if [[ -x "$OMABLUE_SHARE/bin/omablue-theme-generate" ]]; then
      "$OMABLUE_SHARE/bin/omablue-theme-generate" "$theme_path" "$OMABLUE_CONFIG/current" 2>/dev/null || true
    fi

    # Symlink foot theme for foot.ini to include
    if [[ -f "$OMABLUE_CONFIG/current/foot-theme.ini" ]]; then
      ln -sf "$OMABLUE_CONFIG/current/foot-theme.ini" "$HOME/.config/foot/theme.ini"
    fi

    success_msg "Default theme set: $default_theme"
  else
    warn_msg "Default theme not found, skipping theme setup"
  fi
}

# --- Install Dependencies ---
install_dependencies() {
  local deps=(gum fzf)

  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      gum spin --spinner dot --title "Installing $dep..." -- \
        brew install "$dep"
      success_msg "Installed $dep"
    else
      info_msg "$dep already installed"
    fi
  done
}

# --- Configure Shell PATH ---
configure_shell_path() {
  local bin_path="$OMABLUE_SHARE/bin"
  local path_line="export PATH=\"$bin_path:\$PATH\""
  local marker="# --- Omablue Environment ---"

  for shell_rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$shell_rc" ]]; then
      if ! grep -q "$bin_path" "$shell_rc" 2>/dev/null; then
        {
          echo ""
          echo "$marker"
          echo "$path_line"
        } >> "$shell_rc"
        info_msg "Updated $(basename "$shell_rc")"
      else
        info_msg "$(basename "$shell_rc") already configured"
      fi
    fi
  done
}

# --- Show Summary ---
show_summary() {
  echo ""
  gum style \
    --border rounded \
    --border-foreground 42 \
    --padding "1 2" \
    --margin "1 0" \
    "$(gum style --foreground 42 --bold 'Installation Complete!')"

  echo ""
  gum style --foreground 245 "Installed to:"
  echo "  Scripts: $OMABLUE_SHARE/bin/"
  echo "  Themes:  $OMABLUE_SHARE/themes/"
  echo "  Configs: ~/.config/"
  echo ""

  gum style --foreground 245 "Quick start:"
  echo "  • Restart your shell or run: source ~/.bashrc"
  echo "  • Change theme: omablue-theme-selector"
  echo "  • Open menu: omablue-menu (or bind to Super+Space)"
  echo ""

  gum style --foreground 99 "Reload Sway to apply changes: swaymsg reload"
}

# --- Send Notification ---
send_completion_notification() {
  notify-send -u normal -a "Omablue" \
    "Setup Complete" \
    "Omablue has been installed. Reload Sway to apply changes." \
    -h string:x-dunst-stack-tag:setup 2>/dev/null || true
}

# --- Main ---
main() {
  preflight_checks
  show_welcome
  confirm_install

  echo ""
  gum style --foreground 99 --bold "Starting installation..."
  echo ""

  setup_directories
  clone_repo
  backup_configs
  deploy_files
  set_default_theme
  install_dependencies
  configure_shell_path

  show_summary
  send_completion_notification
}

main "$@"
