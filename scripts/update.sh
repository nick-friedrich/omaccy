#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"
source "$REPO_ROOT/scripts/lib/prompts.sh"
source "$REPO_ROOT/scripts/lib/git.sh"

# Fast-forwards the checkout, then rebuilds from it. Rebuilding through install
# also refreshes pristine Omaccy defaults while preserving any user-customized
# canonical config.
#
# Bash reads a script as it executes it, so pulling new code mid-run would
# resume this file at a stale byte offset. The work lives in main(), which bash
# has parsed in full before the pull, and main ends in an exec that replaces
# this process with a fresh read of install.sh.
main() {
  UPDATE_PULLS_CHECKOUT=1
  case "${1:-}" in
    --no-pull) UPDATE_PULLS_CHECKOUT=0 ;;
    "") ;;
    *) echo "Usage: $0 [--no-pull]" >&2; exit 1 ;;
  esac
  if [[ "$#" -gt 1 ]]; then
    echo "Usage: $0 [--no-pull]" >&2
    exit 1
  fi

  # One confirmation covers both the code update and the setup sequence it
  # feeds, so install must not ask again for the same run.
  confirm_setup --update
  if [[ "$UPDATE_PULLS_CHECKOUT" == "1" ]]; then
    update_checkout
  fi
  export OMACCY_SETUP_CONFIRMED=1
  exec bash "$REPO_ROOT/scripts/install.sh" --update
}

main "$@"
