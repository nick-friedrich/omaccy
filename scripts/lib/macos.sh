#!/usr/bin/env bash

# Apply and restore menu-bar and Mission Control preferences.
# Sourced by the entry points; loading this file performs no system changes.

enable_mission_control_grouping() {
  local saved_setting="$OMACCY_DIR/mission-control-group-apps.original"
  local current_value

  if [[ ! -f "$saved_setting" ]]; then
    if current_value="$(defaults read com.apple.dock expose-group-apps 2>/dev/null)"; then
      printf 'value=%s\n' "$current_value" > "$saved_setting"
    else
      printf 'unset\n' > "$saved_setting"
    fi
  fi

  current_value="$(defaults read com.apple.dock expose-group-apps 2>/dev/null || true)"
  if [[ "$current_value" != "1" && "$current_value" != "true" ]]; then
    if ! defaults write com.apple.dock expose-group-apps -bool true; then
      mission_control_grouping_help
      return 0
    fi
  fi

  current_value="$(defaults read com.apple.dock expose-group-apps 2>/dev/null || true)"
  if [[ "$current_value" == "1" || "$current_value" == "true" ]]; then
    echo "Verified Mission Control: Group windows by application is enabled (AeroSpace preview workaround)."
  else
    mission_control_grouping_help
  fi
}

mission_control_grouping_help() {
  echo "WARNING: Could not verify Mission Control window grouping." >&2
  echo "Enable Group windows by application in System Settings → Desktop & Dock → Mission Control." >&2
  echo "Open Desktop & Dock: open 'x-apple.systempreferences:com.apple.preference.dock'" >&2
}

disable_mission_control_arrow_shortcuts() {
  local saved_shortcuts="$OMACCY_DIR/mission-control-arrow-shortcuts.original"
  local prefs_file
  local shortcut_id
  local saved_value
  prefs_file="$(mktemp /tmp/omaccy-symbolic-hotkeys.XXXXXX)"

  if ! defaults export com.apple.symbolichotkeys - > "$prefs_file"; then
    rm -f "$prefs_file"
    echo "WARNING: Could not read macOS Mission Control shortcuts; Hyper+Arrow may conflict." >&2
    return 0
  fi

  # Save each original state only once so repeated installs do not replace it
  # with Omaccy's disabled state. The paired IDs are the normal and internal
  # Shift/slow variants for Mission Control, App Windows, and Spaces left/right.
  if [[ ! -f "$saved_shortcuts" ]]; then
    : > "$saved_shortcuts"
    for shortcut_id in 32 33 34 35 79 80 81 82; do
      if saved_value="$(/usr/libexec/PlistBuddy -c \
          "Print :AppleSymbolicHotKeys:$shortcut_id:enabled" "$prefs_file" 2>/dev/null)"; then
        printf '%s=%s\n' "$shortcut_id" "$saved_value" >> "$saved_shortcuts"
      else
        printf '%s=missing\n' "$shortcut_id" >> "$saved_shortcuts"
      fi
    done
  fi

  for shortcut_id in 32 33 34 35 79 80 81 82; do
    if /usr/libexec/PlistBuddy -c \
        "Print :AppleSymbolicHotKeys:$shortcut_id:enabled" "$prefs_file" >/dev/null 2>&1; then
      /usr/libexec/PlistBuddy -c \
        "Set :AppleSymbolicHotKeys:$shortcut_id:enabled false" "$prefs_file"
    fi
  done

  defaults import com.apple.symbolichotkeys "$prefs_file"
  rm -f "$prefs_file"
  killall cfprefsd 2>/dev/null || true
  echo "Disabled conflicting macOS Mission Control and Spaces arrow shortcuts."
}

restore_mission_control_grouping() {
  local saved_setting="$OMACCY_DIR/mission-control-group-apps.original"
  local saved_value
  [[ -f "$saved_setting" ]] || return 0

  saved_value="$(cat "$saved_setting")"
  case "$saved_value" in
    value=1|value=true)
      defaults write com.apple.dock expose-group-apps -bool true || return 0
      ;;
    value=0|value=false)
      defaults write com.apple.dock expose-group-apps -bool false || return 0
      ;;
    unset)
      if defaults read com.apple.dock expose-group-apps >/dev/null 2>&1; then
        defaults delete com.apple.dock expose-group-apps || return 0
      fi
      ;;
    *)
      echo "WARNING: Invalid saved Mission Control grouping setting; leaving it unchanged." >&2
      return 0
      ;;
  esac
  rm -f "$saved_setting"
  echo "Restored the previous Mission Control window grouping setting."
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
  echo "Restored the previous macOS Mission Control and Spaces shortcuts."
}
