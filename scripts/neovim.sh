#!/usr/bin/env bash
set -euo pipefail

# Turns Omaccy's Neovim config on or off after setup has run, so answering the
# setup question once is not final. `off` restores whatever ~/.config/nvim was
# before and remembers the no, so updates leave it alone rather than linking
# Omaccy's config back in. Neovim and ripgrep are left installed.
#
# Usage: bash scripts/neovim.sh [status | on | off]

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"
source "$REPO_ROOT/scripts/lib/prompts.sh"
source "$REPO_ROOT/scripts/lib/dependencies.sh"
source "$REPO_ROOT/scripts/lib/config.sh"
source "$REPO_ROOT/scripts/lib/neovim.sh"

case "${1:-status}" in
  status)
    if neovim_enabled; then echo on; else echo off; fi
    ;;
  on|off)
    mkdir -p "$CONF_DIR" "$BAK_DIR"
    set_neovim_setup "$1"
    ;;
  *)
    echo "Usage: bash $(basename "$0") [status | on | off]" >&2
    exit 2
    ;;
esac
