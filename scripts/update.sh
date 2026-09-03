#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Rebuilding through install also refreshes pristine Omaccy defaults while
# preserving any user-customized canonical config.
exec "$REPO_ROOT/scripts/install.sh"
