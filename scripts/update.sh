#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Rebuilding through install also refreshes pristine Omaccy defaults while
# preserving any user-customized canonical config.
if [[ "$#" -gt 0 ]]; then
  echo "Usage: $0" >&2
  exit 1
fi
exec bash "$REPO_ROOT/scripts/install.sh" --update
