#!/usr/bin/env bash
set -euo pipefail

# Turns Omaccy's zsh setup on or off after setup has run, so answering the
# setup question once is not final. `off` takes the marked block back out of
# ~/.zshrc, leaving the file as it was, and remembers the no so updates do not
# put it back. Starship and the plugins are left installed.
#
# Usage: bash scripts/zsh.sh [status | on | off]

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"
source "$REPO_ROOT/scripts/lib/prompts.sh"
source "$REPO_ROOT/scripts/lib/dependencies.sh"
source "$REPO_ROOT/scripts/lib/config.sh"
source "$REPO_ROOT/scripts/lib/zsh.sh"

case "${1:-status}" in
  status)
    if zsh_enabled; then echo on; else echo off; fi
    ;;
  on|off)
    mkdir -p "$CONF_DIR" "$BAK_DIR"
    set_zsh_setup "$1"
    ;;
  *)
    echo "Usage: bash $(basename "$0") [status | on | off]" >&2
    exit 2
    ;;
esac
