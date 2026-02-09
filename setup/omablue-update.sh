#!/bin/bash
set -euo pipefail
umask 022

# --- Omablue Update ---
# Idempotent update: pull latest, re-deploy files, re-apply theme
# Safe to run multiple times

# --- Configuration ---
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OMABLUE_SHARE="$HOME/.local/share/omablue"
OMABLUE_CONFIG="$HOME/.config/omablue"
CONFIG_DIRS=(sway waybar rofi dunst foot swaylock Thunar gtk-3.0 nvim)

# shellcheck source=setup/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# --- Git Pull (if inside a git repo) ---
update_repo() {
    msg "Updating repository..."

    if [[ -d "$REPO_DIR/.git" ]]; then
        if git -C "$REPO_DIR" pull --ff-only; then
            ok "repo updated"
        else
            warn "git pull failed (continuing with current files)"
        fi
    else
        ok "not a git repo, skipping pull"
    fi

    msg ""
}

# --- Re-deploy Files (Phase 2) ---
deploy_files() {
    msg "Deploying files..."

    mkdir -p "$OMABLUE_SHARE/bin"
    mkdir -p "$OMABLUE_SHARE/themes"
    mkdir -p "$OMABLUE_SHARE/assets"
    mkdir -p "$OMABLUE_CONFIG/current"

    # Deploy bin scripts
    if [[ -d "$REPO_DIR/bin" ]]; then
        deploy_dir_contents "$REPO_DIR/bin" "$OMABLUE_SHARE/bin"
        find "$OMABLUE_SHARE/bin" -maxdepth 1 -type f -name 'omablue-*' -exec chmod +x {} +
        ok "scripts deployed"
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
                deploy_rofi "$REPO_DIR/config/rofi" "$HOME/.config/rofi"
            else
                deploy_dir_contents "$REPO_DIR/config/$dir" "$HOME/.config/$dir"
            fi
            ok "config/$dir deployed"
        fi
    done

    msg ""
}

# --- Re-apply Theme (Phase 5) ---
reapply_theme() {
    msg "Re-applying theme..."

    local current_dir="$OMABLUE_CONFIG/current"
    local theme_name_file="$current_dir/theme.name"

    # Read current theme name (default to catppuccin)
    local theme_name="catppuccin"
    if [[ -f "$theme_name_file" ]]; then
        theme_name="$(sanitize_name "$(cat "$theme_name_file")")"
    fi
    if [[ -z "$theme_name" ]]; then
        theme_name="catppuccin"
    fi

    local theme_path="$OMABLUE_SHARE/themes/$theme_name"
    if [[ ! -d "$theme_path" ]]; then
        warn "Theme '$theme_name' not found, skipping"
        msg ""
        return
    fi

    mkdir -p "$current_dir"

    # Update symlink
    ln -nsf "$theme_path" "$current_dir/theme"

    # Regenerate theme files
    if [[ -x "$OMABLUE_SHARE/bin/omablue-theme-generate" ]]; then
        "$OMABLUE_SHARE/bin/omablue-theme-generate" "$theme_path" "$current_dir"
        ok "theme files regenerated ($theme_name)"
    fi

    # Re-link foot theme
    if [[ -f "$current_dir/foot-theme.ini" ]]; then
        ln -sf "$current_dir/foot-theme.ini" "$HOME/.config/foot/theme.ini"
    fi

    # Re-link waybar colors
    if [[ -f "$current_dir/waybar-colors.css" ]]; then
        ln -sf "$current_dir/waybar-colors.css" "$HOME/.config/waybar/colors.css"
    fi

    # Re-link rofi colors
    if [[ -f "$current_dir/rofi-colors.rasi" ]]; then
        ln -sf "$current_dir/rofi-colors.rasi" "$HOME/.config/rofi/colors.rasi"
    fi

    # Regenerate dunstrc
    local dunst_base="$HOME/.config/dunst/dunstrc.base"
    local dunst_theme="$current_dir/dunst-theme.conf"
    local dunst_target="$HOME/.config/dunst/dunstrc"
    if [[ -f "$dunst_base" && -f "$dunst_theme" ]]; then
        cat "$dunst_base" "$dunst_theme" > "$dunst_target"
    fi

    msg ""
}

# --- Re-apply PATH (Phase 4, idempotent) ---
reapply_path() {
    msg "Checking shell PATH..."

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

    msg ""
}

# --- Main ---
main() {
    msg ""
    msg "=== Omablue Update ==="
    msg ""

    update_repo
    deploy_files
    reapply_theme
    reapply_path

    # Reload sway
    swaymsg reload 2>/dev/null || true

    notify-send -u normal -a "Omablue" \
        "Update Complete" \
        "Omablue has been updated." \
        -h string:x-dunst-stack-tag:setup 2>/dev/null || true

    msg "Update complete!"
    msg ""
}

main "$@"
