#!/bin/bash
# --- Omablue Shared Library ---
# Sourced by setup, update, and uninstall scripts.
# Do NOT execute this file directly.

# --- Output Helpers (plain text - gum may not be available) ---
msg()  { printf '%s\n' "$1"; }
ok()   { printf '  [OK] %s\n' "$1"; }
warn() { printf '  [!!] %s\n' "$1" >&2; }
err()  { printf '  [ERROR] %s\n' "$1" >&2; }
die()  { err "$1"; exit 1; }

# --- Deploy rofi config excluding .git directories ---
# Usage: deploy_rofi <source_dir> <dest_dir>
deploy_rofi() {
    local src="$1"
    local dst="$2"

    (
        cd "$src" || return 1
        find . -not -path '*/.git/*' -not -name '.git' | while IFS= read -r item; do
            if [[ -d "$src/$item" ]]; then
                mkdir -p "$dst/$item"
            elif [[ -f "$src/$item" ]]; then
                cp "$src/$item" "$dst/$item"
            fi
        done
    )
}

# --- Deploy files from source to destination ---
# Safely copies directory contents, handling empty directories.
# Usage: deploy_dir_contents <source_dir> <dest_dir>
deploy_dir_contents() {
    local src="$1"
    local dst="$2"

    if [[ -d "$src" ]] && compgen -G "$src/*" >/dev/null; then
        cp -r "$src/"* "$dst/"
    fi
}

# --- Sanitize a string to alphanumeric, underscore, and hyphen ---
# Usage: sanitized=$(sanitize_name "$raw_input")
sanitize_name() {
    printf '%s' "$1" | tr -cd '[:alnum:]_-'
}
