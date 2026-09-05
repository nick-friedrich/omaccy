#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/prompts.sh"
source "$REPO_ROOT/scripts/lib/config.sh"

test_dir="$(mktemp -d "${TMPDIR:-/tmp}/omaccy-scripts.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
unset OMACCY_ASSUME_YES

# Approved answers are tested only against the pure prompt helper.
for answer in y Y yes Yes YES; do
  printf '%s\n' "$answer" | ask_confirmation 'Test prompt?' >/dev/null
done
for answer in '' n no maybe; do
  if printf '%s\n' "$answer" | ask_confirmation 'Test prompt?' >/dev/null; then
    echo "FAIL: accepted '$answer'" >&2
    exit 1
  fi
done
if ask_confirmation 'Test prompt?' </dev/null >/dev/null; then
  echo 'FAIL: accepted EOF' >&2
  exit 1
fi

# Each entry point must resolve its libraries from an unrelated directory and
# cancel before any work. Never pass an affirmative answer to these entry points.
for operation in install update uninstall; do
  for answer in '' n maybe; do
    output="$(cd "$test_dir"; printf '%s\n' "$answer" | bash "$REPO_ROOT/scripts/$operation.sh")"
    [[ "$output" == *cancelled.* ]]
    [[ "$(printf '%s' "$output" | grep -o '\[y/N\]' | wc -l | tr -d ' ')" == 1 ]]
  done
  output="$(cd "$test_dir"; bash "$REPO_ROOT/scripts/$operation.sh" </dev/null)"
  [[ "$output" == *cancelled.* ]]
done

# Load controller definitions without its command dispatcher; mock the CLI so
# the disabled-server regression cannot touch desktop apps or services.
sed '/^case "${1:-}" in/,$d' "$REPO_ROOT/scripts/aerospace-control.sh" > "$test_dir/aerospace-functions.sh"
source "$test_dir/aerospace-functions.sh"
AEROSPACE_DISABLED_MARKER="$test_dir/aerospace-disabled"
aerospace_test_state="$test_dir/aerospace-state"
aerospace_test_trace="$test_dir/aerospace-trace"
aerospace() {
  printf '%s\n' "$*" >> "$aerospace_test_trace"
  case "$*" in
    'list-workspaces --all')
      case "$(cat "$aerospace_test_state")" in
        enabled) echo 1 ;;
        disabled) echo "AeroSpace server is disabled and doesn't accept commands." >&2; return 1 ;;
        restricted) echo 'Operation not permitted' >&2; return 1 ;;
      esac
      ;;
    'enable on') echo enabled > "$aerospace_test_state" ;;
    'enable off') echo disabled > "$aerospace_test_state" ;;
    'reload-config --no-gui') [[ "$(cat "$aerospace_test_state")" == enabled ]] ;;
    *) return 1 ;;
  esac
}
echo enabled > "$aerospace_test_state"
stop_aerospace
[[ -f "$AEROSPACE_DISABLED_MARKER" ]]
[[ "$(cat "$aerospace_test_state")" == disabled ]]
start_aerospace
[[ "$(cat "$aerospace_test_state")" == enabled ]]
[[ ! -f "$AEROSPACE_DISABLED_MARKER" ]]
grep -q '^reload-config --no-gui$' "$aerospace_test_trace"
echo restricted > "$aerospace_test_state"
if aerospace_ready_for_start; then
  echo 'FAIL: restricted IPC reported as ready' >&2
  exit 1
fi
ipc_is_restricted
unset -f aerospace

# Exercise real backup/update/restore logic entirely in temporary paths.
OMACCY_DIR="$test_dir/state"
CONF_DIR="$OMACCY_DIR/config"
BAK_DIR="$OMACCY_DIR/backups"
REPO_ROOT="$test_dir/checkout"
mkdir -p "$BAK_DIR" "$REPO_ROOT/config"
printf 'original\n' > "$test_dir/target"
printf 'default-v1\n' > "$REPO_ROOT/config/example"
ensure_symlink "$REPO_ROOT/config/example" "$test_dir/target" >/dev/null
[[ -L "$test_dir/target" ]]
[[ "$(cat "$test_dir/target")" == default-v1 ]]
printf 'default-v2\n' > "$REPO_ROOT/config/example"
ensure_symlink "$REPO_ROOT/config/example" "$test_dir/target" >/dev/null
[[ "$(cat "$test_dir/target")" == default-v2 ]]
printf 'custom\n' > "$CONF_DIR/example"
ensure_symlink "$REPO_ROOT/config/example" "$test_dir/target" >/dev/null
[[ "$(cat "$test_dir/target")" == custom ]]
restore_target "$test_dir/target" "$CONF_DIR/example" >/dev/null
[[ ! -L "$test_dir/target" ]]
[[ "$(cat "$test_dir/target")" == original ]]

echo 'PASS: confirmations, cancellation, AeroSpace re-enable, config updates, and backup restoration.'
