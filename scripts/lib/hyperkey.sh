#!/usr/bin/env bash

# Fetch or build, sign, install, and launch the bundled keyboard app.
# Sourced by the entry points; loading this file performs no system changes.

OMACCY_RELEASE_REPO="nick-friedrich/omaccy"

# Local builds are ad-hoc signed unless a Developer ID Application identity is
# available in the keychain. Developer ID signing keeps one code identity across
# rebuilds: the designated requirement is the bundle identifier plus the team,
# not the binary's hash, so the Accessibility grant survives every rebuild and
# matches the identity of the released app. Set OMACCY_SIGNING_IDENTITY to a
# certificate hash or name to pick one, or to "-" to force ad-hoc signing.
resolve_hyperkey_signing_identity() {
  if [[ -n "${OMACCY_SIGNING_IDENTITY:-}" ]]; then
    printf '%s' "$OMACCY_SIGNING_IDENTITY"
    return
  fi
  # Select by certificate hash: a keychain can hold several certificates
  # sharing one Developer ID name, which codesign rejects as ambiguous.
  security find-identity -v -p codesigning 2>/dev/null \
    | awk '/Developer ID Application/ { print $2; exit }'
}

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
  local mode_stamp="$OMACCY_DIR/hyperkey-signing-mode"
  local built_hash
  local binary_changed=0
  local identity signing_mode
  local previous_mode=""

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
  identity="$(resolve_hyperkey_signing_identity)"
  if [[ -z "$identity" || "$identity" == "-" ]]; then
    signing_mode="adhoc"
    codesign --force --sign - --identifier com.omaccy.hyperkey "$APP_DIR"
  else
    signing_mode="developer-id"
    # --timestamp=none keeps rebuilds fast and working offline; a trusted
    # timestamp matters for distribution, which the release workflow handles.
    codesign --force --options runtime --timestamp=none \
      --sign "$identity" --identifier com.omaccy.hyperkey "$APP_DIR"
  fi
  [[ -f "$mode_stamp" ]] && previous_mode="$(cat "$mode_stamp")"
  printf '%s\n' "$built_hash" > "$build_stamp"
  printf '%s\n' "$signing_mode" > "$mode_stamp"

  # Ad-hoc builds get a new code identity whenever the executable changes, so
  # their TCC entry goes stale. A Developer ID identity only changes when the
  # signing mode itself changes. Config-only updates keep their grant either way.
  if [[ "$signing_mode" != "$previous_mode" ]] \
    || [[ "$signing_mode" == "adhoc" && "$binary_changed" == "1" ]]; then
    tccutil reset Accessibility com.omaccy.hyperkey 2>/dev/null || true
  fi
  if [[ "$signing_mode" == "developer-id" ]]; then
    echo "Signed with Developer ID; the Accessibility grant survives rebuilds."
  else
    echo "Ad-hoc signed; Accessibility must be granted again whenever the binary changes."
  fi
  echo "Installed → $APP_DIR"
}

install_hyperkey_app_from_release() {
  local installed_tag_file="$OMACCY_DIR/hyperkey-release"
  local mode_stamp="$OMACCY_DIR/hyperkey-signing-mode"
  local previous_mode=""
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

  # Released builds carry the same team-scoped identity as a Developer
  # ID-signed local build, so only a previous ad-hoc build leaves a stale
  # TCC entry behind.
  [[ -f "$mode_stamp" ]] && previous_mode="$(cat "$mode_stamp")"
  printf 'developer-id\n' > "$mode_stamp"
  if [[ "$previous_mode" != "developer-id" ]]; then
    tccutil reset Accessibility com.omaccy.hyperkey 2>/dev/null || true
  fi
  echo "Installed Omaccy Hyperkey $tag_name → $APP_DIR"
}

HYPERKEY_LABEL="com.omaccy.hyperkey"

# The single seam every launchd call goes through, so service handling can be
# exercised without touching a real domain.
hyperkey_launchctl() {
  /bin/launchctl "$@"
}

hyperkey_service_target() {
  printf 'gui/%s/%s' "$(id -u)" "$HYPERKEY_LABEL"
}

# Configs and scripts ship continuously from the repository while the app ships
# only on tags, so a freshly pulled checkout can carry app changes the installed
# release does not have. Roughly a quarter of this project's commits touch both
# trees, so a config can land referencing a feature the running binary lacks,
# which reads as a broken setting rather than as a wait for the next release.
# Requires git.sh for checkout_git. A local build removes the release stamp, so
# the absent file correctly reports no skew.
warn_hyperkey_checkout_skew() {
  local installed_tag_file="$OMACCY_DIR/hyperkey-release"
  local installed_tag count plural=s

  [[ -f "$installed_tag_file" ]] || return 0
  installed_tag="$(cat "$installed_tag_file")"
  [[ -n "$installed_tag" ]] || return 0
  command -v git >/dev/null 2>&1 || return 0
  # Only comparable against a checkout whose history actually holds that tag.
  checkout_git rev-parse -q --verify "$installed_tag^{commit}" >/dev/null 2>&1 || return 0
  count="$(checkout_git rev-list --count "$installed_tag..HEAD" -- apps/hyperkey/ 2>/dev/null)" || return 0
  [[ "$count" =~ ^[0-9]+$ ]] || return 0
  [[ "$count" -gt 0 ]] || return 0
  [[ "$count" == 1 ]] && plural=""

  echo ""
  echo "Note: this checkout has $count app change$plural newer than the installed Omaccy"
  echo "Hyperkey $installed_tag. Configs from those commits may reference features it does"
  echo "not have yet; they arrive with the next tagged release."
  printf 'To build them now: OMACCY_HYPERKEY_BUILD_LOCAL=1 bash %q\n' "$REPO_ROOT/scripts/update.sh"
}

stop_hyperkey_process() {
  local waited=0
  hyperkey_launchctl bootout "$(hyperkey_service_target)" >/dev/null 2>&1 || true
  pkill -x omaccy-hyperkey 2>/dev/null || true
  # bootout returns before launchd has finished tearing the job down, and
  # bootstrapping a label still being removed fails. Wait for it to go, but
  # never block setup indefinitely on it.
  while hyperkey_launchctl print "$(hyperkey_service_target)" >/dev/null 2>&1; do
    [[ "$waited" -lt 50 ]] || break
    sleep 0.1
    waited=$((waited + 1))
  done
}

start_hyperkey() {
  local output=""
  # Restart, never a bare start. An agent still loaded from a previous install
  # makes bootstrap fail with "Bootstrap failed: 5: Input/output error", which
  # under errexit aborted the rest of setup — AeroSpace, SketchyBar, and herdr
  # never started. Reloading is also what puts a newly installed binary into
  # service; bootstrapping over a live agent would leave the old one running.
  stop_hyperkey_process
  if output="$(hyperkey_launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT" 2>&1)"; then
    echo "Started Omaccy Hyperkey. If macOS prompts, approve its Accessibility access."
    return 0
  fi

  # A real failure is worth reporting loudly, but not at the cost of the setup
  # steps that follow it.
  [[ -n "$output" ]] && echo "$output" >&2
  echo "Warning: could not start Omaccy Hyperkey's launch agent." >&2
  printf 'Setup continues. Start it by hand with: launchctl bootstrap gui/%s %q\n' \
    "$(id -u)" "$LAUNCH_AGENT" >&2
  return 0
}
