#!/bin/bash
set -euo pipefail
umask 022

# --- Omablue Setup Installer ---
# Interactive installer for Secureblue Sericea Sway configuration
# Deploys from the local repo (no git clone)

# --- Configuration ---
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OMABLUE_SHARE="$HOME/.local/share/omablue"
OMABLUE_CONFIG="$HOME/.config/omablue"
BACKUP_DIRS=(sway waybar rofi dunst foot swaylock Thunar gtk-3.0 nvim)
CONFIG_DIRS=(sway waybar rofi dunst foot swaylock Thunar gtk-3.0 nvim)
BREW_BIN=""

# shellcheck source=setup/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# --- Phase 0: Preflight Checks ---
phase_preflight() {
    msg "Phase 0: Preflight checks"

    # Must not be root
    if [[ "$(id -u)" -eq 0 ]]; then
        die "Do not run this script as root. Run as your regular user."
    fi

    # HOME must be set and writable
    if [[ -z "${HOME:-}" ]]; then
        die "\$HOME is not set."
    fi
    if [[ ! -d "$HOME" || ! -w "$HOME" ]]; then
        die "\$HOME ($HOME) is not a writable directory."
    fi

    # Find brew
    if command -v brew &>/dev/null; then
        BREW_BIN="$(command -v brew)"
    elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
        BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"
        # shellcheck disable=SC2046
        # Safe: BREW_BIN is set from a known, fixed-path binary only
        eval "$("$BREW_BIN" shellenv)"
    elif [[ -x /var/home/linuxbrew/.linuxbrew/bin/brew ]]; then
        BREW_BIN="/var/home/linuxbrew/.linuxbrew/bin/brew"
        # shellcheck disable=SC2046
        # Safe: BREW_BIN is set from a known, fixed-path binary only
        eval "$("$BREW_BIN" shellenv)"
    else
        err "Homebrew (brew) not found."
        msg ""
        msg "Install Homebrew first: see https://brew.sh"
        msg "Then run this setup again."
        exit 1
    fi
    ok "brew found: $BREW_BIN"

    # Check git
    if ! command -v git &>/dev/null; then
        die "git not found in PATH."
    fi
    ok "git found"

    # Check swaymsg
    if ! command -v swaymsg &>/dev/null; then
        die "swaymsg not found. Is this a Sway-based system?"
    fi
    ok "swaymsg found"

    # Verify repo structure
    if [[ ! -d "$REPO_DIR/bin" || ! -d "$REPO_DIR/config" || ! -d "$REPO_DIR/themes" ]]; then
        die "Repo structure invalid. Expected bin/, config/, themes/ in $REPO_DIR"
    fi
    ok "repo structure valid: $REPO_DIR"

    msg ""
}

# --- Phase 1: Backup Existing Configs ---
phase_backup() {
    msg "Phase 1: Backup existing configs"

    local to_backup=()
    for dir in "${BACKUP_DIRS[@]}"; do
        if [[ -d "$HOME/.config/$dir" ]]; then
            to_backup+=("$dir")
        fi
    done

    if [[ ${#to_backup[@]} -eq 0 ]]; then
        ok "nothing to backup"
        msg ""
        return
    fi

    local backup_dir
    backup_dir="$HOME/.config-backup-omablue-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir" || die "Failed to create backup directory: $backup_dir"

    for dir in "${to_backup[@]}"; do
        cp -r "$HOME/.config/$dir" "$backup_dir/" || die "Failed to backup $dir"
        ok "backed up $dir"
    done

    ok "backups saved to $backup_dir"
    msg ""
}

# --- Phase 2: Deploy Files ---
phase_deploy() {
    msg "Phase 2: Deploy files from local repo"

    # Create target directories
    mkdir -p "$OMABLUE_SHARE/bin"
    mkdir -p "$OMABLUE_SHARE/themes"
    mkdir -p "$OMABLUE_SHARE/assets"
    mkdir -p "$OMABLUE_CONFIG/current"

    # Deploy bin scripts
    if [[ -d "$REPO_DIR/bin" ]]; then
        deploy_dir_contents "$REPO_DIR/bin" "$OMABLUE_SHARE/bin"
        find "$OMABLUE_SHARE/bin" -maxdepth 1 -type f -name 'omablue-*' -exec chmod +x {} +
        ok "scripts deployed to $OMABLUE_SHARE/bin/"
    fi

    # Deploy themes
    if [[ -d "$REPO_DIR/themes" ]]; then
        deploy_dir_contents "$REPO_DIR/themes" "$OMABLUE_SHARE/themes"
        ok "themes deployed"
    fi

    # Deploy assets
    if [[ -d "$REPO_DIR/assets" ]]; then
        deploy_dir_contents "$REPO_DIR/assets" "$OMABLUE_SHARE/assets"
        ok "assets deployed"
    fi

    # Deploy config directories
    for dir in "${CONFIG_DIRS[@]}"; do
        if [[ -d "$REPO_DIR/config/$dir" ]]; then
            mkdir -p "$HOME/.config/$dir"

            if [[ "$dir" == "rofi" ]]; then
                # Rofi needs special handling: exclude .git directories
                # from the catppuccin theme submodule
                deploy_rofi "$REPO_DIR/config/rofi" "$HOME/.config/rofi"
            else
                deploy_dir_contents "$REPO_DIR/config/$dir" "$HOME/.config/$dir"
            fi
            ok "config/$dir deployed"
        fi
    done

    msg ""
}

# --- Phase 3: Brew Install ---
phase_brew() {
    msg "Phase 3: Install Homebrew dependencies"

    # Critical packages - abort if these fail
    local critical=(gum fzf)
    for pkg in "${critical[@]}"; do
        if command -v "$pkg" &>/dev/null; then
            ok "$pkg already installed"
        else
            msg "  Installing $pkg..."
            if brew install "$pkg"; then
                ok "$pkg installed"
            else
                die "Failed to install critical package: $pkg"
            fi
        fi
    done

    # Optional packages - warn and continue
    local optional=(jq btop)
    for pkg in "${optional[@]}"; do
        if command -v "$pkg" &>/dev/null; then
            ok "$pkg already installed"
        else
            msg "  Installing $pkg..."
            if brew install "$pkg"; then
                ok "$pkg installed"
            else
                warn "Failed to install optional package: $pkg (continuing)"
            fi
        fi
    done

    msg ""
}

# --- Phase 4: Shell PATH ---
phase_path() {
    msg "Phase 4: Configure shell PATH"

    local bin_path="$OMABLUE_SHARE/bin"
    local marker="# --- Omablue ---"
    local path_line="export PATH=\"\$HOME/.local/share/omablue/bin:\$PATH\""

    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ ! -f "$rc_file" ]]; then
            continue
        fi
        if grep -qF ".local/share/omablue/bin" "$rc_file"; then
            ok "$(basename "$rc_file") already configured"
        else
            printf '\n%s\n%s\n' "$marker" "$path_line" >> "$rc_file"
            ok "$(basename "$rc_file") updated"
        fi
    done

    # Ensure it's in our current PATH for the rest of this script
    export PATH="$bin_path:$PATH"

    msg ""
}

# --- Phase 5: Default Theme (catppuccin) ---
phase_theme() {
    msg "Phase 5: Set default theme (catppuccin)"

    local default_theme="catppuccin"
    local theme_path="$OMABLUE_SHARE/themes/$default_theme"
    local current_dir="$OMABLUE_CONFIG/current"

    if [[ ! -d "$theme_path" ]]; then
        warn "Default theme '$default_theme' not found, skipping"
        msg ""
        return
    fi

    mkdir -p "$current_dir"

    # Create theme symlink
    ln -nsf "$theme_path" "$current_dir/theme"

    # Save theme name
    echo "$default_theme" > "$current_dir/theme.name"

    # Generate theme files (sway, waybar, foot, rofi, dunst)
    if [[ -x "$OMABLUE_SHARE/bin/omablue-theme-generate" ]]; then
        "$OMABLUE_SHARE/bin/omablue-theme-generate" "$theme_path" "$current_dir"
        ok "theme files generated"
    else
        warn "omablue-theme-generate not found, skipping generation"
    fi

    # Symlink foot theme
    if [[ -f "$current_dir/foot-theme.ini" ]]; then
        mkdir -p "$HOME/.config/foot"
        ln -sf "$current_dir/foot-theme.ini" "$HOME/.config/foot/theme.ini"
        ok "foot theme linked"
    fi

    # Symlink waybar colors
    if [[ -f "$current_dir/waybar-colors.css" ]]; then
        mkdir -p "$HOME/.config/waybar"
        ln -sf "$current_dir/waybar-colors.css" "$HOME/.config/waybar/colors.css"
        ok "waybar colors linked"
    fi

    # Symlink rofi colors
    if [[ -f "$current_dir/rofi-colors.rasi" ]]; then
        mkdir -p "$HOME/.config/rofi"
        ln -sf "$current_dir/rofi-colors.rasi" "$HOME/.config/rofi/colors.rasi"
        ok "rofi colors linked"
    fi

    # Concatenate dunstrc.base + dunst theme → dunstrc
    local dunst_base="$HOME/.config/dunst/dunstrc.base"
    local dunst_theme="$current_dir/dunst-theme.conf"
    local dunst_target="$HOME/.config/dunst/dunstrc"
    if [[ -f "$dunst_base" && -f "$dunst_theme" ]]; then
        cat "$dunst_base" "$dunst_theme" > "$dunst_target"
        ok "dunstrc generated"
    fi

    msg ""
}

# --- Phase 6: Battery Monitor (opt-in) ---
phase_battery() {
    msg "Phase 6: Battery monitor service (optional)"

    local response=""
    if command -v gum &>/dev/null; then
        if gum confirm "Enable battery monitor service?"; then
            response="y"
        fi
    else
        read -rp "  Enable battery monitor service? [y/N] " response
    fi

    if [[ "${response,,}" != "y" ]]; then
        ok "skipped"
        msg ""
        return
    fi

    local service_dir="$HOME/.config/systemd/user"
    mkdir -p "$service_dir"

    # Write service unit
    cat > "$service_dir/omablue-battery.service" << EOF
[Unit]
Description=Omablue Battery Monitor

[Service]
Type=oneshot
ExecStart=$HOME/.local/share/omablue/bin/omablue-battery-monitor
EOF

    # Write timer unit
    cat > "$service_dir/omablue-battery.timer" << EOF
[Unit]
Description=Omablue Battery Monitor Timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
AccuracySec=30s

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now omablue-battery.timer
    ok "battery monitor enabled"
    msg ""
}

# --- Phase 7: Reload + Summary ---
phase_summary() {
    msg "Phase 7: Reload and summary"

    # Reload sway (ignore failure - might not be in a sway session)
    swaymsg reload 2>/dev/null || true

    # Send notification (ignore failure)
    notify-send -u normal -a "Omablue" \
        "Setup Complete" \
        "Omablue has been installed. Your Sway config is live." \
        -h string:x-dunst-stack-tag:setup 2>/dev/null || true

    msg ""
    msg "============================================"
    msg "  Omablue setup complete!"
    msg "============================================"
    msg ""
    msg "  Installed to:"
    msg "    Scripts: $OMABLUE_SHARE/bin/"
    msg "    Themes:  $OMABLUE_SHARE/themes/"
    msg "    Config:  $OMABLUE_CONFIG/"
    msg ""
    msg "  Key commands:"
    msg "    omablue-menu             Main launcher (Super+Esc)"
    msg "    omablue-theme-selector   Change theme"
    msg ""
    msg "  Remember to reload your shell:"
    msg "    source ~/.bashrc"
    msg ""
}

# --- Main ---
main() {
    msg ""
    msg "=== Omablue Setup ==="
    msg ""

    phase_preflight
    phase_backup
    phase_deploy
    phase_brew
    phase_path
    phase_theme
    phase_battery
    phase_summary
}

main "$@"
