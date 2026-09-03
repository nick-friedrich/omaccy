#!/usr/bin/env bash
set -euo pipefail

OMACCY_DIR="$HOME/.omaccy"
CONF_DIR="$OMACCY_DIR/config"
BAK_DIR="$OMACCY_DIR/backups"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$HOME/Applications/Omaccy Hyperkey.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.omaccy.hyperkey.plist"

mkdir -p "$CONF_DIR" "$BAK_DIR"

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
  echo "Building Omaccy Hyperkey..."
  swift build -c release --package-path "$REPO_ROOT/apps/hyperkey"

  /bin/launchctl bootout "gui/$(id -u)/com.omaccy.hyperkey" 2>/dev/null || true
  pkill -x omaccy-hyperkey 2>/dev/null || true

  mkdir -p "$APP_DIR/Contents/MacOS"
  cp "$REPO_ROOT/apps/hyperkey/.build/release/omaccy-hyperkey" \
    "$APP_DIR/Contents/MacOS/omaccy-hyperkey"
  cp "$REPO_ROOT/apps/hyperkey/Info.plist" "$APP_DIR/Contents/Info.plist"
  codesign --force --sign - --identifier com.omaccy.hyperkey "$APP_DIR"
  # Ad-hoc local builds have a new code hash; clear any stale TCC entry so the
  # system prompt reflects the binary that was just installed.
  tccutil reset Accessibility com.omaccy.hyperkey 2>/dev/null || true
  echo "Installed → $APP_DIR"
}

start_hyperkey() {
  /bin/launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"
  echo "Started Omaccy Hyperkey. Approve its Accessibility prompt to finish setup."
}

main() {
  migrate_legacy_karabiner_config
  install_hyperkey_app
  ensure_symlink "$REPO_ROOT/config/hyperkey/hyperkey.toml" \
    "$HOME/.config/omaccy/hyperkey.toml"
  ensure_symlink "$REPO_ROOT/config/launchagents/com.omaccy.hyperkey.plist" \
    "$LAUNCH_AGENT"
  start_hyperkey
  echo ""
  echo "Omaccy Hyperkey installed: Caps Lock → Command+Control+Option (no Shift)."
}

main
