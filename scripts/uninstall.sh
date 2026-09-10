#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"
source "$REPO_ROOT/scripts/lib/prompts.sh"
source "$REPO_ROOT/scripts/lib/dependencies.sh"
source "$REPO_ROOT/scripts/lib/config.sh"
source "$REPO_ROOT/scripts/lib/macos.sh"
source "$REPO_ROOT/scripts/lib/fonts.sh"
# Keep-awake state belongs to the bar plugin; uninstall shares its reader so
# there is one definition of which files hold it and when the recorded PID may
# be signalled. The library derives its paths from OMACCY_STATE_DIR at source
# time, so that has to be set first.
OMACCY_STATE_DIR="$OMACCY_DIR"
source "$REPO_ROOT/config/sketchybar/lib/caffeinate-state.sh"

# Keep-awake deliberately outlives SketchyBar, so stopping the service does not
# end it. caffeinate_stop confirms the recorded PID is still caffeinate before
# signalling it, which matters here: a PID reused since an earlier boot would
# otherwise have uninstall kill an unrelated process.
stop_owned_caffeinate() {
  caffeinate_stop
}

# Omaccy only ever changed the light/dark appearance if the switch was turned
# on, and then it recorded what it found first -- so this puts that back, the
# way the other macOS preferences are restored.
restore_macos_appearance() {
  local original="$OMACCY_DIR/appearance.original"
  [[ -f "$original" ]] || return 0
  local dark="true"
  [[ "$(head -n 1 "$original" | tr -d '[:space:]')" == "light" ]] && dark="false"
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $dark" \
    >/dev/null 2>&1 || echo "Could not restore the macOS appearance; set it yourself in System Settings > Appearance." >&2
  rm -f "$original"
}

# VS Code's and Cursor's settings.json are the user's own files, edited in
# place rather than symlinked, so removing Omaccy must not rewrite them: the
# theme they are on now may well be one they want to keep, and anything they
# changed since would be lost. The untouched original is kept instead, and
# named here so restoring it stays their call.
report_editor_settings() {
  local backup
  for backup in "$OMACCY_DIR/backups"/*-settings.json; do
    [[ -f "$backup" ]] || continue
    echo "Left in place: $(basename "${backup%-settings.json}") keeps its current theme; the pre-Omaccy settings are at $backup."
  done
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
  restore_target "$HOME/.config/aerospace/layout.sh" \
    "$CONF_DIR/aerospace/layout.sh"
  # Retired in 0.4.2 and removed by install.sh, so this only finds anything on
  # a machine that is being uninstalled without having been updated first.
  restore_target "$HOME/.config/aerospace/master-stack.sh" \
    "$CONF_DIR/aerospace/master-stack.sh"
  restore_target "$HOME/.config/aerospace/aerospace.toml" \
    "$CONF_DIR/aerospace/aerospace.toml"
  restore_target "$HOME/.config/sketchybar/sketchybarrc" \
    "$CONF_DIR/sketchybar/sketchybarrc"
  # Globbed over the installed copies, matching the plugin loop below, so a
  # library added after this machine was set up is still restored.
  local sketchybar_lib
  for sketchybar_lib in "$CONF_DIR"/sketchybar/lib/*.sh; do
    [[ -e "$sketchybar_lib" ]] || continue
    restore_target "$HOME/.config/sketchybar/lib/$(basename "$sketchybar_lib")" \
      "$sketchybar_lib"
  done
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
  rm -f "$OMACCY_DIR/hyperkey-release" \
    "$OMACCY_DIR/hyperkey-checkout.txt" \
    "$OMACCY_DIR/hyperkey-build.sha256" \
    "$OMACCY_DIR/hyperkey-signing-mode"
  rm -f "$CONF_DIR/launchagents/com.omaccy.hyperkey.plist" \
    "$CONF_DIR/hyperkey/hyperkey.toml" \
    "$CONF_DIR/ghostty/config.ghostty" \
    "$CONF_DIR/aerospace/dock-toggle.sh" \
    "$CONF_DIR/aerospace/layout.sh" \
    "$CONF_DIR/aerospace/master-stack.sh" \
    "$CONF_DIR/aerospace/aerospace.toml" \
    "$CONF_DIR/sketchybar/sketchybarrc" \
    "$CONF_DIR/sketchybar/lib/palette.sh" \
    "$CONF_DIR/sketchybar/lib/aerospace.sh" \
    "$CONF_DIR/sketchybar/lib/icons.sh" \
    "$CONF_DIR/sketchybar/plugins/"*.sh \
    "$CONF_DIR/sketchybar/themes/"*.sh \
    "$OMACCY_DIR/theme" \
    "$OMACCY_DIR/font" \
    "$OMACCY_DIR/editor-theme" \
    "$OMACCY_DIR/appearance" \
    "$OMACCY_DIR/sha256/launchagents/com.omaccy.hyperkey.plist" \
    "$OMACCY_DIR/sha256/hyperkey/hyperkey.toml" \
    "$OMACCY_DIR/sha256/ghostty/config.ghostty" \
    "$OMACCY_DIR/sha256/aerospace/dock-toggle.sh" \
    "$OMACCY_DIR/sha256/aerospace/layout.sh" \
    "$OMACCY_DIR/sha256/aerospace/master-stack.sh" \
    "$OMACCY_DIR/sha256/aerospace/aerospace.toml" \
    "$OMACCY_DIR/sha256/sketchybar/sketchybarrc" \
    "$OMACCY_DIR/sha256/sketchybar/lib/palette.sh" \
    "$OMACCY_DIR/sha256/sketchybar/lib/aerospace.sh" \
    "$OMACCY_DIR/sha256/sketchybar/lib/icons.sh" \
    "$OMACCY_DIR/sha256/sketchybar/plugins/"*.sh \
    "$OMACCY_DIR/sha256/sketchybar/themes/"*.sh
  rm -f "$OMACCY_DIR/aerospace-disabled" \
    "$OMACCY_DIR/native-menu-visible"
  rm -rf "$OMACCY_DIR/clipboard" "$OMACCY_DIR/workspace-layout"
  restore_macos_appearance
  report_editor_settings

  remove_owned_cask ghostty Ghostty
  remove_owned_cask aerospace AeroSpace
  remove_owned_cask font-inter "the Inter font"
  remove_owned_cask font-jetbrains-mono "the JetBrains Mono font"
  remove_owned_cask font-lora "the Lora font"
  remove_owned_sf_pro_font
  remove_owned_formula sketchybar SketchyBar
  # Only stop herdr's service if Omaccy installed herdr: it can host the
  # user's own unrelated agent sessions, and stopping it would kill those too.
  if [[ -f "$OMACCY_DIR/installed-formulas" ]] && grep -qx herdr "$OMACCY_DIR/installed-formulas"; then
    brew services stop herdr || true
  fi
  remove_owned_formula herdr Herdr
  if [[ -f "$OMACCY_DIR/sketchybar-service-was-running" ]] && command -v sketchybar >/dev/null 2>&1; then
    brew services start sketchybar || true
    rm -f "$OMACCY_DIR/sketchybar-service-was-running"
    echo "Restarted the user's pre-existing SketchyBar service."
  fi
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
