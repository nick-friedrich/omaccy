#!/usr/bin/env bash

# Shared by setup and dependency-removal prompts. Only an explicit yes proceeds.
ask_confirmation() {
  local prompt="$1"
  local answer
  if [[ "${OMACCY_ASSUME_YES:-0}" == "1" ]]; then
    echo "$prompt [automatically confirmed: OMACCY_ASSUME_YES=1]"
    return 0
  fi
  printf '%s [y/N] ' "$prompt"
  if ! read -r answer; then
    echo
    return 1
  fi
  case "$answer" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

confirm_setup() {
  local setup_action=Install
  case "${1:-}" in
    --update) setup_action=Update ;;
    "") ;;
    *) echo "Usage: $0 [--update]" >&2; exit 1 ;;
  esac
  if [[ "$#" -gt 1 ]]; then
    echo "Usage: $0 [--update]" >&2
    exit 1
  fi

  echo "$setup_action Omaccy"
  if [[ "$setup_action" == "Update" ]]; then
    echo "Rebuild from this local checkout and refresh unchanged default configs; keep customized configs."
    echo "This does not download newer repository code or upgrade existing Homebrew packages."
  fi
  echo "This will:"
  echo "  - Install Homebrew if needed, plus missing Ghostty, AeroSpace, and SketchyBar dependencies."
  echo "  - Install/rebuild Omaccy Hyperkey, configure launch at login, and map Caps Lock to Command+Control+Option."
  echo "  - Back up existing configs before replacing their paths with Omaccy symlinks."
  echo "  - Start AeroSpace and enable SketchyBar as a background service at login; restart Omaccy Hyperkey."
  echo "  - Hide the native menu bar, disable conflicting Mission Control arrow shortcuts,"
  echo "    enable window grouping, and restart the Dock and menu-bar services."
  echo "  - Possibly require Accessibility access again if the app binary changes."
  echo "Config backups: $BAK_DIR (timestamped originals, restored on uninstall)."
  echo "Editable Omaccy configs: $CONF_DIR (customizations are preserved during updates)."
  printf 'To uninstall later: bash %q\n' "$REPO_ROOT/scripts/uninstall.sh"
  if ! ask_confirmation "Proceed with $setup_action?"; then
    echo "$setup_action cancelled."
    exit 0
  fi
}

confirm_uninstall() {
  echo "Uninstall Omaccy"
  echo "This will stop Omaccy Hyperkey, AeroSpace tiling, and SketchyBar; restore normal Caps Lock;"
  echo "remove the Omaccy app and managed configs; and restore backed-up configs and macOS settings."
  echo "The Dock and menu-bar services will restart. A previously running SketchyBar service will be restarted."
  echo "You will be asked separately before removing dependencies installed by Omaccy."
  echo "Pre-existing dependencies and Homebrew will remain installed."
  echo "Original configs will be restored from $BAK_DIR where their paths are still managed by Omaccy."
  echo "Omaccy's editable configs in $CONF_DIR will be removed; copy any customizations you want to keep."
  if ! ask_confirmation "Proceed with uninstall?"; then
    echo "Uninstall cancelled."
    exit 0
  fi
}
