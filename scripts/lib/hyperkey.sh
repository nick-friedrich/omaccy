#!/usr/bin/env bash

# Build, sign, install, and launch the bundled keyboard app.
# Sourced by the entry points; loading this file performs no system changes.

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
