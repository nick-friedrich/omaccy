#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"
source "$REPO_ROOT/scripts/lib/prompts.sh"
source "$REPO_ROOT/scripts/lib/dependencies.sh"
source "$REPO_ROOT/scripts/lib/config.sh"
source "$REPO_ROOT/scripts/lib/macos.sh"
source "$REPO_ROOT/scripts/lib/hyperkey.sh"

main() {
  confirm_setup "$@"
  mkdir -p "$CONF_DIR" "$BAK_DIR"

  migrate_legacy_karabiner_config
  ensure_cask ghostty
  ensure_cask aerospace nikitabobko/tap/aerospace
  ensure_cask font-inter
  ensure_cask font-jetbrains-mono
  ensure_cask font-lora
  ensure_formula sketchybar FelixKratz/formulae/sketchybar
  ensure_formula herdr
  if grep -qx sketchybar "$OMACCY_DIR/preinstalled-formulas" 2>/dev/null && \
      brew services list 2>/dev/null | grep -q '^sketchybar[[:space:]].*started'; then
    touch "$OMACCY_DIR/sketchybar-service-was-running"
  fi
  ensure_symlink "$REPO_ROOT/config/ghostty/config.ghostty" \
    "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
  ensure_absent_with_backup "$HOME/.aerospace.toml"
  ensure_symlink "$REPO_ROOT/config/aerospace/aerospace.toml" \
    "$HOME/.config/aerospace/aerospace.toml"
  ensure_symlink "$REPO_ROOT/config/aerospace/master-stack.sh" \
    "$HOME/.config/aerospace/master-stack.sh"
  ensure_symlink "$REPO_ROOT/config/aerospace/dock-toggle.sh" \
    "$HOME/.config/aerospace/dock-toggle.sh"
  chmod +x "$CONF_DIR/aerospace/master-stack.sh"
  chmod +x "$CONF_DIR/aerospace/dock-toggle.sh"
  disable_mission_control_arrow_shortcuts
  enable_mission_control_grouping
  killall Dock 2>/dev/null || true
  ensure_symlink "$REPO_ROOT/config/sketchybar/sketchybarrc" \
    "$HOME/.config/sketchybar/sketchybarrc"
  local sketchybar_plugin
  for sketchybar_plugin in "$REPO_ROOT"/config/sketchybar/plugins/*.sh; do
    ensure_symlink "$sketchybar_plugin" \
      "$HOME/.config/sketchybar/plugins/$(basename "$sketchybar_plugin")"
    chmod +x "$CONF_DIR/sketchybar/plugins/$(basename "$sketchybar_plugin")"
  done
  chmod +x "$CONF_DIR/sketchybar/sketchybarrc"
  ensure_symlink "$REPO_ROOT/config/sketchybar/lib/palette.sh" \
    "$HOME/.config/sketchybar/lib/palette.sh"
  ensure_symlink "$REPO_ROOT/config/sketchybar/lib/aerospace.sh" \
    "$HOME/.config/sketchybar/lib/aerospace.sh"
  local sketchybar_theme
  for sketchybar_theme in "$REPO_ROOT"/config/sketchybar/themes/*.sh; do
    ensure_symlink "$sketchybar_theme" \
      "$HOME/.config/sketchybar/themes/$(basename "$sketchybar_theme")"
  done
  install_hyperkey_app
  ensure_symlink "$REPO_ROOT/config/hyperkey/hyperkey.toml" \
    "$HOME/.config/omaccy/hyperkey.toml"
  ensure_symlink "$REPO_ROOT/config/launchagents/com.omaccy.hyperkey.plist" \
    "$LAUNCH_AGENT"
  start_hyperkey
  echo "Starting AeroSpace tiling..."
  "$REPO_ROOT/scripts/aerospace-control.sh" start
  echo "Starting SketchyBar and enabling its background service at login..."
  brew services restart sketchybar
  echo "Starting herdr's background service at login..."
  # start, not restart: herdr keeps agent sessions alive across terminal
  # closures, so an already-running instance must not be killed and relaunched.
  # ensure_login_service explains a bootstrap that loses to an already-running
  # herdr rather than reporting it as a failure.
  ensure_login_service herdr
  echo ""
  echo "Omaccy installed: Caps Lock → Command+Control+Option; Hyper+T → Ghostty; AeroSpace tiling and SketchyBar enabled."
  printf 'To uninstall: bash %q\n' "$REPO_ROOT/scripts/uninstall.sh"
  echo "Original config backups: $BAK_DIR"
}

main "$@"
