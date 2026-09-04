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

remove_owned_formula() {
  local formula="$1"
  local display_name="$2"
  local marker="$OMACCY_DIR/installed-formulas"
  [[ -f "$marker" ]] && grep -qx "$formula" "$marker" || return 0

  if ask_confirmation "Remove $display_name, which Omaccy installed?"; then
    brew uninstall "$formula" || true
    local updated_marker="$OMACCY_DIR/installed-formulas.updated"
    grep -vx "$formula" "$marker" > "$updated_marker" || true
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

restore_native_menu_bar_autohide() {
  local saved_setting="$OMACCY_DIR/native-menubar-autohide.original"
  local saved_option="$OMACCY_DIR/native-menubar-autohide-option.original"
  [[ -f "$saved_setting" || -f "$saved_option" ]] || return 0

  local saved_value
  if [[ -f "$saved_setting" ]]; then
    saved_value="$(cat "$saved_setting")"
    case "$saved_value" in
      value=1|value=true) defaults write NSGlobalDomain _HIHideMenuBar -bool true ;;
      value=0|value=false) defaults write NSGlobalDomain _HIHideMenuBar -bool false ;;
      unset) defaults delete NSGlobalDomain _HIHideMenuBar 2>/dev/null || true ;;
    esac
  fi

  if [[ -f "$saved_option" ]]; then
    saved_value="$(cat "$saved_option")"
    case "$saved_value" in
      value=*) defaults write com.apple.controlcenter AutoHideMenuBarOption -int "${saved_value#value=}" ;;
      unset) defaults delete com.apple.controlcenter AutoHideMenuBarOption 2>/dev/null || true ;;
    esac
  fi

  rm -f "$saved_setting"
  rm -f "$saved_option"
  killall ControlCenter 2>/dev/null || true
  killall SystemUIServer 2>/dev/null || true
  echo "Restored the previous native menu-bar auto-hide setting."
}

restore_mission_control_arrow_shortcuts() {
  local saved_shortcuts="$OMACCY_DIR/mission-control-arrow-shortcuts.original"
  local prefs_file
  local shortcut_id
  local saved_value
  [[ -f "$saved_shortcuts" ]] || return 0

  prefs_file="$(mktemp /tmp/omaccy-symbolic-hotkeys.XXXXXX)"
  if ! defaults export com.apple.symbolichotkeys - > "$prefs_file"; then
    rm -f "$prefs_file"
    echo "WARNING: Could not restore the previous macOS Mission Control shortcuts." >&2
    return 0
  fi

  while IFS='=' read -r shortcut_id saved_value; do
    case "$saved_value" in
      true|false)
        if /usr/libexec/PlistBuddy -c \
            "Print :AppleSymbolicHotKeys:$shortcut_id:enabled" "$prefs_file" >/dev/null 2>&1; then
          /usr/libexec/PlistBuddy -c \
            "Set :AppleSymbolicHotKeys:$shortcut_id:enabled $saved_value" "$prefs_file"
        fi
        ;;
    esac
  done < "$saved_shortcuts"

  defaults import com.apple.symbolichotkeys "$prefs_file"
  rm -f "$prefs_file" "$saved_shortcuts"
  killall cfprefsd 2>/dev/null || true
  killall Dock 2>/dev/null || true
  echo "Restored the previous macOS Mission Control and Spaces shortcuts."
}

main() {
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

  restore_target "$HOME/Library/LaunchAgents/com.omaccy.hyperkey.plist" \
    "$CONF_DIR/launchagents/com.omaccy.hyperkey.plist"
  restore_target "$HOME/.config/omaccy/hyperkey.toml" \
    "$CONF_DIR/hyperkey/hyperkey.toml"
  restore_target "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty" \
    "$CONF_DIR/ghostty/config.ghostty"
  restore_target "$HOME/.config/aerospace/master-stack.sh" \
    "$CONF_DIR/aerospace/master-stack.sh"
  restore_target "$HOME/.config/aerospace/aerospace.toml" \
    "$CONF_DIR/aerospace/aerospace.toml"
  restore_target "$HOME/.config/sketchybar/sketchybarrc" \
    "$CONF_DIR/sketchybar/sketchybarrc"
  local sketchybar_plugin
  for sketchybar_plugin in "$CONF_DIR"/sketchybar/plugins/*.sh; do
    [[ -e "$sketchybar_plugin" ]] || continue
    restore_target "$HOME/.config/sketchybar/plugins/$(basename "$sketchybar_plugin")" \
      "$sketchybar_plugin"
  done
  restore_displaced_target "$HOME/.aerospace.toml"
  if command -v aerospace >/dev/null 2>&1 && aerospace list-workspaces --all >/dev/null 2>&1; then
    aerospace reload-config --no-gui || true
  fi

  rm -rf "$APP_DIR"
  rm -f "$CONF_DIR/launchagents/com.omaccy.hyperkey.plist" \
    "$CONF_DIR/hyperkey/hyperkey.toml" \
    "$CONF_DIR/ghostty/config.ghostty" \
    "$CONF_DIR/aerospace/master-stack.sh" \
    "$CONF_DIR/aerospace/aerospace.toml" \
    "$CONF_DIR/sketchybar/sketchybarrc" \
    "$CONF_DIR/sketchybar/plugins/"*.sh \
    "$OMACCY_DIR/sha256/launchagents/com.omaccy.hyperkey.plist" \
    "$OMACCY_DIR/sha256/hyperkey/hyperkey.toml" \
    "$OMACCY_DIR/sha256/ghostty/config.ghostty" \
    "$OMACCY_DIR/sha256/aerospace/master-stack.sh" \
    "$OMACCY_DIR/sha256/aerospace/aerospace.toml" \
    "$OMACCY_DIR/sha256/sketchybar/sketchybarrc" \
    "$OMACCY_DIR/sha256/sketchybar/plugins/"*.sh
  rm -f "$OMACCY_DIR/aerospace-disabled" \
    "$OMACCY_DIR/native-menu-visible"

  remove_owned_cask ghostty Ghostty
  remove_owned_cask aerospace AeroSpace
  remove_owned_formula sketchybar SketchyBar
  if [[ -f "$OMACCY_DIR/sketchybar-service-was-running" ]] && command -v sketchybar >/dev/null 2>&1; then
    brew services start sketchybar || true
    rm -f "$OMACCY_DIR/sketchybar-service-was-running"
    echo "Restarted the user's pre-existing SketchyBar service."
  fi
  restore_native_menu_bar_autohide
  rmdir "$HOME/.config/omaccy" 2>/dev/null || true
  rmdir "$HOME/.config/aerospace" 2>/dev/null || true
  rmdir "$CONF_DIR/aerospace" 2>/dev/null || true
  rmdir "$HOME/.config/sketchybar/plugins" 2>/dev/null || true
  rmdir "$HOME/.config/sketchybar" 2>/dev/null || true
  rmdir "$CONF_DIR/sketchybar/plugins" 2>/dev/null || true
  rmdir "$CONF_DIR/sketchybar" 2>/dev/null || true
  echo "Omaccy removed; AeroSpace tiling stopped, SketchyBar restored, and Caps Lock restored."
}

main
