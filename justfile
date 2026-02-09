# Omablue - Sway rice for secureblue
# https://github.com/odd-git/omablue

REPO_DIR := justfile_directory()

# List available recipes
default:
    @just --list --unsorted

# Full setup of the omablue environment
setup-omablue:
    @bash "{{REPO_DIR}}/setup/omablue-setup.sh"

# Update omablue from current repo state
update-omablue:
    @bash "{{REPO_DIR}}/setup/omablue-update.sh"

# Clean uninstall of omablue
uninstall-omablue:
    @bash "{{REPO_DIR}}/setup/omablue-uninstall.sh"

# Browse recipes interactively with gum
choose:
    @just --chooser "gum filter --placeholder 'Pick a recipe...'" --choose
