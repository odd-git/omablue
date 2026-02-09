#!/bin/bash
set -euo pipefail
umask 022

# --- Omablue Uninstall ---
# Removes omablue scripts, themes, and generated config
# Does NOT remove ~/.config/sway etc. (may have user modifications)

OMABLUE_SHARE="$HOME/.local/share/omablue"
OMABLUE_CONFIG="$HOME/.config/omablue"

# shellcheck source=setup/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# --- Confirmation ---
confirm_uninstall() {
    msg ""
    msg "=== Omablue Uninstall ==="
    msg ""
    msg "This will remove:"
    msg "  - $OMABLUE_SHARE/"
    msg "  - $OMABLUE_CONFIG/"
    msg "  - Omablue PATH entries from .bashrc/.zshrc"
    msg "  - Battery monitor service (if active)"
    msg ""
    msg "This will NOT remove:"
    msg "  - ~/.config/sway, waybar, rofi, etc. (may have your changes)"
    msg "  - Config backups (~/.config-backup-omablue-*)"
    msg ""

    local response=""
    if command -v gum &>/dev/null; then
        if ! gum confirm "Proceed with uninstall?"; then
            msg "Cancelled."
            exit 0
        fi
    else
        read -rp "Proceed with uninstall? [y/N] " response
        if [[ "${response,,}" != "y" ]]; then
            msg "Cancelled."
            exit 0
        fi
    fi
}

# --- Stop Battery Timer ---
stop_battery_timer() {
    msg "Checking battery monitor service..."

    if systemctl --user is-active omablue-battery.timer &>/dev/null; then
        systemctl --user stop omablue-battery.timer
        ok "timer stopped"
    fi

    if systemctl --user is-enabled omablue-battery.timer &>/dev/null; then
        systemctl --user disable omablue-battery.timer
        ok "timer disabled"
    fi

    # Remove unit files
    local service_dir="$HOME/.config/systemd/user"
    for unit in omablue-battery.service omablue-battery.timer; do
        if [[ -f "$service_dir/$unit" ]]; then
            rm "$service_dir/$unit"
            ok "removed $unit"
        fi
    done

    if [[ -d "$HOME/.config/systemd/user" ]]; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi
}

# --- Remove PATH from Shell RC Files ---
remove_path() {
    msg "Removing PATH entries..."

    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ ! -f "$rc_file" ]]; then
            continue
        fi

        if grep -qF ".local/share/omablue/bin" "$rc_file"; then
            # Remove the omablue marker and PATH line
            local tmp
            tmp="$(mktemp)"
            trap 'rm -f "$tmp"' EXIT
            grep -vF ".local/share/omablue/bin" "$rc_file" \
                | grep -v '^# --- Omablue ---$' > "$tmp"
            mv "$tmp" "$rc_file"
            trap - EXIT
            ok "cleaned $(basename "$rc_file")"
        fi
    done
}

# --- Remove Omablue Directories ---
remove_dirs() {
    msg "Removing omablue directories..."

    if [[ -d "$OMABLUE_SHARE" ]]; then
        rm -rf "$OMABLUE_SHARE"
        ok "removed $OMABLUE_SHARE"
    fi

    if [[ -d "$OMABLUE_CONFIG" ]]; then
        rm -rf "$OMABLUE_CONFIG"
        ok "removed $OMABLUE_CONFIG"
    fi
}

# --- Main ---
main() {
    confirm_uninstall

    msg ""
    stop_battery_timer
    remove_path
    remove_dirs

    msg ""
    msg "Omablue has been uninstalled."
    msg ""

    # Check for backup directories
    local found_backups=false
    for bdir in "$HOME"/.config-backup-omablue-*; do
        if [[ -d "$bdir" ]]; then
            if [[ "$found_backups" == false ]]; then
                msg "Your config backups are still available:"
                found_backups=true
            fi
            msg "  $bdir"
        fi
    done
    if [[ "$found_backups" == true ]]; then
        msg ""
        msg "To restore, copy them back to ~/.config/"
    fi

    msg ""
}

main "$@"
