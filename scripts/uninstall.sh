#!/usr/bin/env bash
set -euo pipefail

OMACCY_DIR="$HOME/.omaccy"
CONF_DIR="$OMACCY_DIR/config"
BAK_DIR="$OMACCY_DIR/backups"
APP_DIR="$HOME/Applications/Omaccy Hyperkey.app"

restore_target() {
  local target="$1"
  local canonical="$2"
  local backup

  if [[ ! -L "$target" || "$(readlink "$target")" != "$canonical" ]]; then
    echo "Not an Omaccy symlink → $target (left as-is)"
    return
  fi

  rm "$target"
  backup="$(find "$BAK_DIR" -maxdepth 1 -type f -name "$(basename "$target").*" -print 2>/dev/null | sort | tail -n 1)"
  if [[ -n "$backup" ]]; then
    mv "$backup" "$target"
    echo "Restored original config → $target"
  else
    echo "Removed Omaccy symlink → $target"
  fi
}

main() {
  /bin/launchctl bootout "gui/$(id -u)/com.omaccy.hyperkey" 2>/dev/null || true
  pkill -x omaccy-hyperkey 2>/dev/null || true

  # Restore normal Caps Lock even if the application has already disappeared.
  /usr/bin/hidutil property --set '{"UserKeyMapping":[]}' >/dev/null

  restore_target "$HOME/Library/LaunchAgents/com.omaccy.hyperkey.plist" \
    "$CONF_DIR/launchagents/com.omaccy.hyperkey.plist"
  restore_target "$HOME/.config/omaccy/hyperkey.toml" \
    "$CONF_DIR/hyperkey/hyperkey.toml"

  rm -rf "$APP_DIR"
  rm -f "$CONF_DIR/launchagents/com.omaccy.hyperkey.plist" \
    "$CONF_DIR/hyperkey/hyperkey.toml" \
    "$OMACCY_DIR/sha256/launchagents/com.omaccy.hyperkey.plist" \
    "$OMACCY_DIR/sha256/hyperkey/hyperkey.toml"

  rmdir "$HOME/.config/omaccy" 2>/dev/null || true
  echo "Omaccy Hyperkey removed; Caps Lock restored."
}

main
