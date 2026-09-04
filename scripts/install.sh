#!/usr/bin/env bash
set -euo pipefail

OMACCY_DIR="$HOME/.omaccy"
CONF_DIR="$OMACCY_DIR/config"
BAK_DIR="$OMACCY_DIR/backups"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$HOME/Applications/Omaccy Hyperkey.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.omaccy.hyperkey.plist"

mkdir -p "$CONF_DIR" "$BAK_DIR"

ensure_brew() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  echo "Homebrew not found — installing..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    echo "ERROR: Homebrew installation failed." >&2
    exit 1
  fi
}

record_dep() {
  local marker="$1"
  local cask="$2"
  touch "$OMACCY_DIR/$marker"
  grep -qx "$cask" "$OMACCY_DIR/$marker" || echo "$cask" >> "$OMACCY_DIR/$marker"
}

ensure_cask() {
  local cask="$1"
  local install_ref="${2:-$cask}"
  ensure_brew

  if brew list --cask "$cask" >/dev/null 2>&1; then
    if [[ -f "$OMACCY_DIR/installed-deps" ]] && grep -qx "$cask" "$OMACCY_DIR/installed-deps"; then
      echo "$cask already installed by Omaccy."
    else
      record_dep preinstalled-deps "$cask"
      echo "$cask already installed; Omaccy will leave it installed on uninstall."
    fi
    return
  fi

  echo "Installing $cask..."
  brew install --cask "$install_ref"
  record_dep installed-deps "$cask"
}

ensure_formula() {
  local formula="$1"
  local install_ref="${2:-$formula}"
  ensure_brew

  if brew list --formula "$formula" >/dev/null 2>&1; then
    if [[ -f "$OMACCY_DIR/installed-formulas" ]] && grep -qx "$formula" "$OMACCY_DIR/installed-formulas"; then
      echo "$formula already installed by Omaccy."
    else
      record_dep preinstalled-formulas "$formula"
      echo "$formula already installed; Omaccy will leave it installed on uninstall."
    fi
    return
  fi

  echo "Installing $formula..."
  brew install "$install_ref"
  record_dep installed-formulas "$formula"
}

stamp_config() {
  local rel="$1"
  local stamp_file="$OMACCY_DIR/sha256/$rel"
  mkdir -p "$(dirname "$stamp_file")"
  shasum -a 256 "$CONF_DIR/$rel" | awk '{print $1}' > "$stamp_file"
}

config_is_pristine() {
  local rel="$1"
  local stamp_file="$OMACCY_DIR/sha256/$rel"
  [[ -f "$stamp_file" && -f "$CONF_DIR/$rel" ]] || return 1
  [[ "$(cat "$stamp_file")" == "$(shasum -a 256 "$CONF_DIR/$rel" | awk '{print $1}')" ]]
}

enable_native_menu_bar_autohide() {
  local saved_setting="$OMACCY_DIR/native-menubar-autohide.original"
  local saved_option="$OMACCY_DIR/native-menubar-autohide-option.original"
  local current_value
  local had_legacy_saved_setting=0
  [[ -f "$saved_setting" ]] && had_legacy_saved_setting=1

  if [[ ! -f "$saved_setting" ]]; then
    if current_value="$(defaults read NSGlobalDomain _HIHideMenuBar 2>/dev/null)"; then
      printf 'value=%s\n' "$current_value" > "$saved_setting"
    else
      printf 'unset\n' > "$saved_setting"
    fi
  fi

  if [[ ! -f "$saved_option" ]]; then
    if [[ "$had_legacy_saved_setting" == "1" ]]; then
      # Migrate installations made by the first SketchyBar installer revision,
      # which wrote only the legacy key. Tahoe's corresponding prior UI value
      # was "In Full Screen Only".
      printf 'value=2\n' > "$saved_option"
    elif current_value="$(defaults read com.apple.controlcenter AutoHideMenuBarOption 2>/dev/null)"; then
      printf 'value=%s\n' "$current_value" > "$saved_option"
    else
      printf 'unset\n' > "$saved_option"
    fi
  fi

  defaults write com.apple.controlcenter AutoHideMenuBarOption -int 0
  defaults write NSGlobalDomain _HIHideMenuBar -bool true
  killall ControlCenter 2>/dev/null || true
  killall SystemUIServer 2>/dev/null || true
  echo "Enabled native menu-bar auto-hide for the SketchyBar replacement."
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
  killall Dock 2>/dev/null || true
  echo "Disabled conflicting macOS Mission Control and Spaces arrow shortcuts."
}

# Copy a repository default into ~/.omaccy/config and link the path consumed by
# macOS or the app. A customized canonical copy is never overwritten.
ensure_symlink() {
  local repo_path="$1"
  local target_path="$2"
  local rel="${repo_path#"$REPO_ROOT/config/"}"
  local canonical="$CONF_DIR/$rel"

  mkdir -p "$(dirname "$canonical")" "$(dirname "$target_path")"

  if [[ ! -e "$canonical" && ! -L "$canonical" ]]; then
    cp "$repo_path" "$canonical"
    stamp_config "$rel"
    echo "Installed canonical config → $canonical"
  elif [[ -L "$canonical" ]]; then
    rm "$canonical"
    cp "$repo_path" "$canonical"
    stamp_config "$rel"
    echo "Re-established canonical config → $canonical"
  elif config_is_pristine "$rel"; then
    if ! cmp -s "$repo_path" "$canonical"; then
      cp "$repo_path" "$canonical"
      stamp_config "$rel"
      echo "Updated canonical config → $canonical"
    fi
  else
    echo "Canonical config customized by user → $canonical (left as-is)"
  fi

  if [[ -L "$target_path" && "$(readlink "$target_path")" == "$canonical" ]]; then
    echo "Already symlinked → $target_path"
    return
  fi

  if [[ -e "$target_path" || -L "$target_path" ]]; then
    local backup="$BAK_DIR/$(basename "$target_path").$(date +%Y%m%d-%H%M%S)"
    mv "$target_path" "$backup"
    echo "Backed up existing $target_path → $backup"
  fi
  ln -s "$canonical" "$target_path"
  echo "Symlinked $target_path → $canonical"
}

# AeroSpace also reads ~/.aerospace.toml and rejects startup when both config
# locations exist. Preserve that alternate config while Omaccy's XDG config is
# active, then let uninstall restore it.
ensure_absent_with_backup() {
  local target_path="$1"

  if [[ -e "$target_path" || -L "$target_path" ]]; then
    local backup="$BAK_DIR/$(basename "$target_path").$(date +%Y%m%d-%H%M%S)"
    mv "$target_path" "$backup"
    echo "Backed up conflicting $target_path → $backup"
  fi
}

migrate_legacy_karabiner_config() {
  local old_target="$HOME/.config/karabiner/karabiner.json"
  if [[ -L "$old_target" && "$(readlink "$old_target")" == "$CONF_DIR/karabiner/karabiner.json" ]]; then
    rm "$old_target"
    local backup
    backup="$(find "$BAK_DIR" -maxdepth 1 -type f -name 'karabiner.json.*' -print 2>/dev/null | sort | tail -n 1)"
    if [[ -n "$backup" ]]; then
      mv "$backup" "$old_target"
      echo "Restored pre-Omaccy Karabiner config → $old_target"
    fi
    echo "Removed the retired Omaccy Karabiner mapping."
  fi
}

install_hyperkey_app() {
  local built_binary="$REPO_ROOT/apps/hyperkey/.build/release/omaccy-hyperkey"
  local installed_binary="$APP_DIR/Contents/MacOS/omaccy-hyperkey"
  local build_stamp="$OMACCY_DIR/hyperkey-build.sha256"
  local built_hash
  local binary_changed=0

  echo "Building Omaccy Hyperkey..."
  swift build -c release --package-path "$REPO_ROOT/apps/hyperkey"
  built_hash="$(shasum -a 256 "$built_binary" | awk '{print $1}')"

  # codesign changes the installed Mach-O, so comparing it directly with the
  # unsigned build always reports a false difference. Track the build hash.
  if [[ ! -f "$installed_binary" || ! -f "$build_stamp" || "$(cat "$build_stamp")" != "$built_hash" ]]; then
    binary_changed=1
  fi

  /bin/launchctl bootout "gui/$(id -u)/com.omaccy.hyperkey" 2>/dev/null || true
  pkill -x omaccy-hyperkey 2>/dev/null || true

  mkdir -p "$APP_DIR/Contents/MacOS"
  cp "$built_binary" "$installed_binary"
  cp "$REPO_ROOT/apps/hyperkey/Info.plist" "$APP_DIR/Contents/Info.plist"
  codesign --force --sign - --identifier com.omaccy.hyperkey "$APP_DIR"
  printf '%s\n' "$built_hash" > "$build_stamp"
  if [[ "$binary_changed" == "1" ]]; then
    # Ad-hoc local builds have a new code hash; clear stale TCC state only when
    # the executable actually changed. Config-only updates keep their grant.
    tccutil reset Accessibility com.omaccy.hyperkey 2>/dev/null || true
  fi
  echo "Installed → $APP_DIR"
}

start_hyperkey() {
  /bin/launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"
  echo "Started Omaccy Hyperkey. If macOS prompts, approve its Accessibility access."
}

main() {
  migrate_legacy_karabiner_config
  ensure_cask ghostty
  ensure_cask aerospace nikitabobko/tap/aerospace
  ensure_formula sketchybar FelixKratz/formulae/sketchybar
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
  chmod +x "$CONF_DIR/aerospace/master-stack.sh"
  disable_mission_control_arrow_shortcuts
  ensure_symlink "$REPO_ROOT/config/sketchybar/sketchybarrc" \
    "$HOME/.config/sketchybar/sketchybarrc"
  local sketchybar_plugin
  for sketchybar_plugin in "$REPO_ROOT"/config/sketchybar/plugins/*.sh; do
    ensure_symlink "$sketchybar_plugin" \
      "$HOME/.config/sketchybar/plugins/$(basename "$sketchybar_plugin")"
    chmod +x "$CONF_DIR/sketchybar/plugins/$(basename "$sketchybar_plugin")"
  done
  chmod +x "$CONF_DIR/sketchybar/sketchybarrc"
  install_hyperkey_app
  ensure_symlink "$REPO_ROOT/config/hyperkey/hyperkey.toml" \
    "$HOME/.config/omaccy/hyperkey.toml"
  ensure_symlink "$REPO_ROOT/config/launchagents/com.omaccy.hyperkey.plist" \
    "$LAUNCH_AGENT"
  start_hyperkey
  "$REPO_ROOT/scripts/aerospace-control.sh" start
  brew services restart sketchybar
  enable_native_menu_bar_autohide
  echo ""
  echo "Omaccy installed: Caps Lock → Command+Control+Option; Hyper+T → Ghostty; AeroSpace tiling and SketchyBar enabled."
}

main
