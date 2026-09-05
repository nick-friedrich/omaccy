#!/usr/bin/env bash

# Shared paths only. Create directories after the user confirms the operation.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OMACCY_DIR="$HOME/.omaccy"
CONF_DIR="$OMACCY_DIR/config"
BAK_DIR="$OMACCY_DIR/backups"
APP_DIR="$HOME/Applications/Omaccy Hyperkey.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.omaccy.hyperkey.plist"
