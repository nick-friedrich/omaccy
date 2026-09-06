#!/usr/bin/env bash

# Fetch or build, sign, install, and launch the bundled keyboard app.
# Sourced by the entry points; loading this file performs no system changes.

OMACCY_RELEASE_REPO="nick-friedrich/omaccy"

# Default path: download the Developer ID-signed, notarized app CI publishes
# for tagged releases. Set OMACCY_HYPERKEY_BUILD_LOCAL=1 to build from the
# current checkout instead, for Swift changes not yet released.
install_hyperkey_app() {
  if [[ "${OMACCY_HYPERKEY_BUILD_LOCAL:-0}" == "1" ]]; then
    install_hyperkey_app_from_source
  else
    install_hyperkey_app_from_release
  fi
  # Kept outside the signed app bundle: writing into an already-notarized
  # bundle's Resources after the fact would invalidate its signature.
  printf '%s' "$REPO_ROOT" > "$OMACCY_DIR/hyperkey-checkout.txt"
}

install_hyperkey_app_from_source() {
  local built_binary="$REPO_ROOT/apps/hyperkey/.build/release/omaccy-hyperkey"
  local installed_binary="$APP_DIR/Contents/MacOS/omaccy-hyperkey"
  local build_stamp="$OMACCY_DIR/hyperkey-build.sha256"
  local built_hash
  local binary_changed=0

  echo "Building Omaccy Hyperkey from source (OMACCY_HYPERKEY_BUILD_LOCAL=1)..."
  swift build -c release --package-path "$REPO_ROOT/apps/hyperkey"
  built_hash="$(shasum -a 256 "$built_binary" | awk '{print $1}')"

  # codesign changes the installed Mach-O, so comparing it directly with the
  # unsigned build always reports a false difference. Track the build hash.
  if [[ ! -f "$installed_binary" || ! -f "$build_stamp" || "$(cat "$build_stamp")" != "$built_hash" ]]; then
    binary_changed=1
  fi

  stop_hyperkey_process
  rm -f "$OMACCY_DIR/hyperkey-release"

  mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
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

install_hyperkey_app_from_release() {
  local installed_tag_file="$OMACCY_DIR/hyperkey-release"
  local release_json tag_name zip_url sha_url

  echo "Checking latest Omaccy Hyperkey release..."
  release_json="$(curl -fsSL "https://api.github.com/repos/$OMACCY_RELEASE_REPO/releases/latest")" || {
    echo "ERROR: Unable to reach GitHub to check the Omaccy Hyperkey release." >&2
    exit 1
  }
  tag_name="$(printf '%s' "$release_json" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]*)".*/\1/')"
  zip_url="$(printf '%s' "$release_json" | grep -o '"browser_download_url": *"[^"]*\.zip"' | sed -E 's/.*"(https[^"]*)"/\1/' | head -n1)"
  sha_url="$(printf '%s' "$release_json" | grep -o '"browser_download_url": *"[^"]*\.zip\.sha256"' | sed -E 's/.*"(https[^"]*)"/\1/' | head -n1)"
  if [[ -z "$tag_name" || -z "$zip_url" || -z "$sha_url" ]]; then
    echo "ERROR: No usable Omaccy Hyperkey release found at github.com/$OMACCY_RELEASE_REPO/releases/latest" >&2
    exit 1
  fi

  if [[ -f "$installed_tag_file" && "$(cat "$installed_tag_file")" == "$tag_name" && -d "$APP_DIR" ]]; then
    echo "Omaccy Hyperkey $tag_name already installed."
    return
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/omaccy-hyperkey.XXXXXX")"

  echo "Downloading Omaccy Hyperkey $tag_name..."
  curl -fsSL "$zip_url" -o "$tmp_dir/app.zip"
  curl -fsSL "$sha_url" -o "$tmp_dir/app.zip.sha256"

  local expected_hash actual_hash
  expected_hash="$(awk '{print $1}' "$tmp_dir/app.zip.sha256")"
  actual_hash="$(shasum -a 256 "$tmp_dir/app.zip" | awk '{print $1}')"
  if [[ -z "$expected_hash" || "$expected_hash" != "$actual_hash" ]]; then
    echo "ERROR: Omaccy Hyperkey download checksum mismatch." >&2
    rm -rf "$tmp_dir"
    exit 1
  fi

  ditto -x -k "$tmp_dir/app.zip" "$tmp_dir/extracted"
  local extracted_app
  extracted_app="$(find "$tmp_dir/extracted" -maxdepth 1 -name "*.app" | head -n1)"
  if [[ -z "$extracted_app" ]]; then
    echo "ERROR: Omaccy Hyperkey release archive did not contain an app bundle." >&2
    rm -rf "$tmp_dir"
    exit 1
  fi

  stop_hyperkey_process
  rm -rf "$APP_DIR"
  mkdir -p "$(dirname "$APP_DIR")"
  ditto "$extracted_app" "$APP_DIR"
  rm -rf "$tmp_dir"
  printf '%s' "$tag_name" > "$installed_tag_file"
  rm -f "$OMACCY_DIR/hyperkey-build.sha256"
  echo "Installed Omaccy Hyperkey $tag_name → $APP_DIR"
}

stop_hyperkey_process() {
  /bin/launchctl bootout "gui/$(id -u)/com.omaccy.hyperkey" 2>/dev/null || true
  pkill -x omaccy-hyperkey 2>/dev/null || true
}

start_hyperkey() {
  /bin/launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"
  echo "Started Omaccy Hyperkey. If macOS prompts, approve its Accessibility access."
}
