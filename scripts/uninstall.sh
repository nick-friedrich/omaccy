#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"
source "$REPO_ROOT/scripts/lib/prompts.sh"
source "$REPO_ROOT/scripts/lib/dependencies.sh"
source "$REPO_ROOT/scripts/lib/config.sh"
source "$REPO_ROOT/scripts/lib/macos.sh"

stop_owned_caffeinate() {
  local pid_file="$OMACCY_DIR/caffeinate.pid"
  local pid=""

  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pid_file" "$OMACCY_DIR/caffeinate.ends-at"
}

main() {
  confirm_uninstall

  if command -v brew >/dev/null 2>&1 && brew services list 2>/dev/null | grep -q '^sketchybar[[:space:]]'; then
    brew services stop sketchybar || true
  fi
  stop_owned_caffeinate
  if command -v aerospace >/dev/null 2>&1; then
    "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/aerospace-control.sh" stop || true
  fi
  /bin/launchctl bootout "gui/$(id -u)/com.omaccy.hyperkey" 2>/dev/null || true
  pkill -x omaccy-hyperkey 2>/dev/null || true

  # Restore normal Caps Lock even if the application has already disappeared.
  /usr/bin/hidutil property --set '{"UserKeyMapping":[]}' >/dev/null

  restore_mission_control_arrow_shortcuts
  restore_mission_control_grouping
  killall Dock 2>/dev/null || true

  restore_target "$HOME/Library/LaunchAgents/com.omaccy.hyperkey.plist" \
    "$CONF_DIR/launchagents/com.omaccy.hyperkey.plist"
  restore_target "$HOME/.config/omaccy/hyperkey.toml" \
    "$CONF_DIR/hyperkey/hyperkey.toml"
  restore_target "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty" \
    "$CONF_DIR/ghostty/config.ghostty"
  restore_target "$HOME/.config/aerospace/dock-toggle.sh" \
    "$CONF_DIR/aerospace/dock-toggle.sh"
  restore_target "$HOME/.config/aerospace/master-stack.sh" \
    "$CONF_DIR/aerospace/master-stack.sh"
  restore_target "$HOME/.config/aerospace/aerospace.toml" \
    "$CONF_DIR/aerospace/aerospace.toml"
  restore_target "$HOME/.config/sketchybar/sketchybarrc" \
    "$CONF_DIR/sketchybar/sketchybarrc"
  restore_target "$HOME/.config/sketchybar/lib/palette.sh" \
    "$CONF_DIR/sketchybar/lib/palette.sh"
  local sketchybar_plugin
  for sketchybar_plugin in "$CONF_DIR"/sketchybar/plugins/*.sh; do
    [[ -e "$sketchybar_plugin" ]] || continue
    restore_target "$HOME/.config/sketchybar/plugins/$(basename "$sketchybar_plugin")" \
      "$sketchybar_plugin"
  done
  local sketchybar_theme
  for sketchybar_theme in "$CONF_DIR"/sketchybar/themes/*.sh; do
    [[ -e "$sketchybar_theme" ]] || continue
    restore_target "$HOME/.config/sketchybar/themes/$(basename "$sketchybar_theme")" \
      "$sketchybar_theme"
  done
  restore_displaced_target "$HOME/.aerospace.toml"
  if command -v aerospace >/dev/null 2>&1 && aerospace list-workspaces --all >/dev/null 2>&1; then
    aerospace reload-config --no-gui || true
  fi

  rm -rf "$APP_DIR"
  rm -f "$CONF_DIR/launchagents/com.omaccy.hyperkey.plist" \
    "$CONF_DIR/hyperkey/hyperkey.toml" \
    "$CONF_DIR/ghostty/config.ghostty" \
    "$CONF_DIR/aerospace/dock-toggle.sh" \
    "$CONF_DIR/aerospace/master-stack.sh" \
    "$CONF_DIR/aerospace/aerospace.toml" \
    "$CONF_DIR/sketchybar/sketchybarrc" \
    "$CONF_DIR/sketchybar/lib/palette.sh" \
    "$CONF_DIR/sketchybar/plugins/"*.sh \
    "$CONF_DIR/sketchybar/themes/"*.sh \
    "$OMACCY_DIR/theme" \
    "$OMACCY_DIR/font" \
    "$OMACCY_DIR/sha256/launchagents/com.omaccy.hyperkey.plist" \
    "$OMACCY_DIR/sha256/hyperkey/hyperkey.toml" \
    "$OMACCY_DIR/sha256/ghostty/config.ghostty" \
    "$OMACCY_DIR/sha256/aerospace/dock-toggle.sh" \
    "$OMACCY_DIR/sha256/aerospace/master-stack.sh" \
    "$OMACCY_DIR/sha256/aerospace/aerospace.toml" \
    "$OMACCY_DIR/sha256/sketchybar/sketchybarrc" \
    "$OMACCY_DIR/sha256/sketchybar/lib/palette.sh" \
    "$OMACCY_DIR/sha256/sketchybar/plugins/"*.sh \
    "$OMACCY_DIR/sha256/sketchybar/themes/"*.sh
  rm -f "$OMACCY_DIR/aerospace-disabled" \
    "$OMACCY_DIR/native-menu-visible"

  remove_owned_cask ghostty Ghostty
  remove_owned_cask aerospace AeroSpace
  remove_owned_cask font-inter "the Inter font"
  remove_owned_cask font-jetbrains-mono "the JetBrains Mono font"
  remove_owned_cask font-lora "the Lora font"
  remove_owned_formula sketchybar SketchyBar
  remove_owned_formula herdr Herdr
  if [[ -f "$OMACCY_DIR/sketchybar-service-was-running" ]] && command -v sketchybar >/dev/null 2>&1; then
    brew services start sketchybar || true
    rm -f "$OMACCY_DIR/sketchybar-service-was-running"
    echo "Restarted the user's pre-existing SketchyBar service."
  fi
  restore_native_menu_bar_autohide
  rmdir "$HOME/.config/omaccy" 2>/dev/null || true
  rmdir "$HOME/.config/aerospace" 2>/dev/null || true
  rmdir "$CONF_DIR/aerospace" 2>/dev/null || true
  rmdir "$HOME/.config/sketchybar/lib" 2>/dev/null || true
  rmdir "$CONF_DIR/sketchybar/lib" 2>/dev/null || true
  rmdir "$HOME/.config/sketchybar/themes" 2>/dev/null || true
  rmdir "$CONF_DIR/sketchybar/themes" 2>/dev/null || true
  rmdir "$HOME/.config/sketchybar/plugins" 2>/dev/null || true
  rmdir "$HOME/.config/sketchybar" 2>/dev/null || true
  rmdir "$CONF_DIR/sketchybar/plugins" 2>/dev/null || true
  rmdir "$CONF_DIR/sketchybar" 2>/dev/null || true
  echo "Omaccy removed; AeroSpace tiling stopped, SketchyBar restored, and Caps Lock restored."
}

main "$@"
