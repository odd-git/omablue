# Omablue

Omablue aims to be the definitive "Omarchy-inspired" experience for secureblue. It is designed for users who demand a seamless, keyboard-driven tiling window manager environment on top of an ultra-secure, hardened Fedora Atomic base.

## The Vision

This project bridges the gap between high-level security and modern aesthetics. As a Project Manager with a passion for Open Source, Privacy, and Security, I have initiated this mockup/MVP to demonstrate how a hardened system can be both beautiful and highly functional.

The goal is to provide a "state of the art" Sway configuration that respects the immutable nature of the host system while offering a fluid, keyboard-centric workflow.

## Core Principles

Security-First: Built for the secureblue ecosystem.

Atomic-Friendly: Prioritizes Flatpak, Homebrew, and ujust over host-level layering.

Keyboard Dominance: Optimized for Sway/Wayland with minimal mouse interaction.

Minimalist Aesthetics: Clean, functional UI with integrated notification handling via Dunst.

## 🛠 Features & Roadmap

The project is currently in its early stages (MVP). Contributions from the community and experienced developers are highly encouraged.

[ ] Setup Script: Automated deployment via ujust integration (In Progress).

[ ] Themes: High-contrast and modern palettes (Catppuccin/Gruvbox).

[x] Omablue Menu: Custom launcher for system utilities.

[x] Security-Hardened Utilities:

[x] Screenshot utility (Wayland native).

[x] Webapp manager (Isolated browser instances).

[x] Flatpak integration.

[x] System Management (TUI/CLI):

[x] Network management.

[x] Bluetooth control.

[x] Audio/Pipewire integration.

[ ] TUI Tooling: Integrated btop, lazygit, and lazydocker overlays.

## Getting Started

Prerequisites

A working installation of Secureblue Sericea.

Installation

Clone the repository:

git clone [https://github.com/your-username/omablue.git](https://github.com/your-username/omablue.git)


Deploy the assets:
cd omablue/
Move the omablue folder to your local share directory:

mv omablue/ ~/.local/share/

Move the assets inside config folder to you local .config directory
mv config/* ~/.config


Update Path:
Ensure your script directory is in your $PATH (e.g., in .bashrc or .zshrc):

export PATH="$HOME/.local/share/omablue/scripts:$PATH"


## Contributing & Credits

This project is inspired by omarchy and many of the utility are based on the omarchy or at least ispired by them. 

A significant portion of the logic in these scripts was inspired by or adapted from community efforts (including vibecoding and AI-assisted drafts).

Note on Security: I am aware that the secureblue maintainers prioritize human-audited code. This project serves as a functional mockup; I invite developers to audit, refactor, and improve these scripts to reach the highest standards of the secureblue project.

If you find a bug or have a feature request, please open an issue.

