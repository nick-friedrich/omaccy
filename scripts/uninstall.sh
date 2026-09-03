#!/usr/bin/env bash
set -euo pipefail

OMACCY_DIR="$HOME/.omaccy"
CONF_DIR="$OMACCY_DIR/config"
BAK_DIR="$OMACCY_DIR/backups"
APP_DIR="$HOME/Applications/Omaccy Hyperkey.app"

ask_confirmation() {
  local prompt="$1"
  if [[ "${OMACCY_ASSUME_YES:-0}" == "1" ]]; then
    return 0
  fi
  printf '%s [y/N] ' "$prompt"
  local answer
  read -r answer
  answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
  [[ "$answer" == "y" || "$answer" == "yes" ]]
}

remove_owned_cask() {
  local cask="$1"
  local display_name="$2"
  local marker="$OMACCY_DIR/installed-deps"
  [[ -f "$marker" ]] && grep -qx "$cask" "$marker" || return 0

  if ask_confirmation "Remove $display_name, which Omaccy installed?"; then
    brew uninstall --cask "$cask" || true
    local updated_marker="$OMACCY_DIR/installed-deps.updated"
    grep -vx "$cask" "$marker" > "$updated_marker" || true
    mv "$updated_marker" "$marker"
    echo "Removed Omaccy-installed $display_name."
  else
    echo "Keeping $display_name installed."
  fi
}

restore_target() {
  local target="$1"
  local canonical="$2"
  local backup

  if [[ ! -L "$target" || "$(readlink "$target")" != "$canonical" ]]; then
    echo "Not an Omaccy symlink → $target (left as-is)"
    return
  fi

  rm "$target"
  backup="$(find "$BAK_DIR" -maxdepth 1 \( -type f -o -type l \) -name "$(basename "$target").*" -print 2>/dev/null | sort | tail -n 1)"
  if [[ -n "$backup" ]]; then
    mv "$backup" "$target"
    echo "Restored original config → $target"
  else
    echo "Removed Omaccy symlink → $target"
  fi
}

restore_displaced_target() {
  local target="$1"
  local backup

  if [[ -e "$target" || -L "$target" ]]; then
    echo "A new config exists → $target (left as-is)"
    return
  fi

  backup="$(find "$BAK_DIR" -maxdepth 1 \( -type f -o -type l \) -name "$(basename "$target").*" -print 2>/dev/null | sort | tail -n 1)"
  if [[ -n "$backup" ]]; then
    mv "$backup" "$target"
    echo "Restored original config → $target"
  fi
}

main() {
  if command -v aerospace >/dev/null 2>&1; then
    "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/aerospace-control.sh" stop || true
  fi
  /bin/launchctl bootout "gui/$(id -u)/com.omaccy.hyperkey" 2>/dev/null || true
  pkill -x omaccy-hyperkey 2>/dev/null || true

  # Restore normal Caps Lock even if the application has already disappeared.
  /usr/bin/hidutil property --set '{"UserKeyMapping":[]}' >/dev/null

  restore_target "$HOME/Library/LaunchAgents/com.omaccy.hyperkey.plist" \
    "$CONF_DIR/launchagents/com.omaccy.hyperkey.plist"
  restore_target "$HOME/.config/omaccy/hyperkey.toml" \
    "$CONF_DIR/hyperkey/hyperkey.toml"
  restore_target "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty" \
    "$CONF_DIR/ghostty/config.ghostty"
  restore_target "$HOME/.config/aerospace/aerospace.toml" \
    "$CONF_DIR/aerospace/aerospace.toml"
  restore_displaced_target "$HOME/.aerospace.toml"
  if command -v aerospace >/dev/null 2>&1 && aerospace list-workspaces --all >/dev/null 2>&1; then
    aerospace reload-config --no-gui || true
  fi

  rm -rf "$APP_DIR"
  rm -f "$CONF_DIR/launchagents/com.omaccy.hyperkey.plist" \
    "$CONF_DIR/hyperkey/hyperkey.toml" \
    "$CONF_DIR/ghostty/config.ghostty" \
    "$CONF_DIR/aerospace/aerospace.toml" \
    "$OMACCY_DIR/sha256/launchagents/com.omaccy.hyperkey.plist" \
    "$OMACCY_DIR/sha256/hyperkey/hyperkey.toml" \
    "$OMACCY_DIR/sha256/ghostty/config.ghostty" \
    "$OMACCY_DIR/sha256/aerospace/aerospace.toml"

  remove_owned_cask ghostty Ghostty
  remove_owned_cask aerospace AeroSpace
  rmdir "$HOME/.config/omaccy" 2>/dev/null || true
  rmdir "$HOME/.config/aerospace" 2>/dev/null || true
  rmdir "$CONF_DIR/aerospace" 2>/dev/null || true
  echo "Omaccy removed; AeroSpace tiling stopped and Caps Lock restored."
}

main
