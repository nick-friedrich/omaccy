#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/prompts.sh"
source "$REPO_ROOT/scripts/lib/config.sh"
source "$REPO_ROOT/scripts/lib/dependencies.sh"
source "$REPO_ROOT/scripts/lib/hyperkey.sh"

# The macOS system bash (3.2) does not apply `set -e` to a failing [[ ]], and
# its ERR trap does not fire for one either, so a bare conditional is a check
# that can never fail. Every assertion here reports through this instead.
fail() {
  echo "FAIL: $*" >&2
  exit 1
}

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

# Starting the keyboard agent, with launchd and the process kill mocked. An
# update that leaves the app version unchanged never unloads the agent, so a
# bare bootstrap hits an already-loaded label; the restart must absorb that
# rather than aborting every setup step that follows it.
LAUNCH_AGENT="$test_dir/com.omaccy.hyperkey.plist"
agent_loaded=1
bootstrap_result=0
launchctl_trace="$test_dir/launchctl-trace"
hyperkey_launchctl() {
  printf '%s\n' "$1" >> "$launchctl_trace"
  case "$1" in
    bootout) agent_loaded=0 ;;
    print) [[ "$agent_loaded" == 1 ]] ;;
    bootstrap)
      if [[ "$bootstrap_result" == 0 ]]; then
        agent_loaded=1
        return 0
      fi
      echo "Bootstrap failed: 5: Input/output error" >&2
      return 1
      ;;
  esac
}
pkill() { :; }

: > "$launchctl_trace"
output="$(start_hyperkey 2>&1)" || fail "starting the agent reported failure"
[[ "$output" == *"Started Omaccy Hyperkey"* ]] || fail "a started agent did not report success"
[[ "$output" != *Warning* ]] || fail "a started agent printed a warning"
grep -q '^bootout$' "$launchctl_trace" || fail "start did not unload the agent first"
[[ "$(grep -n '^bootout$' "$launchctl_trace" | head -1 | cut -d: -f1)" \
   -lt "$(grep -n '^bootstrap$' "$launchctl_trace" | head -1 | cut -d: -f1)" ]] \
  || fail "start bootstrapped before unloading the loaded agent"

# A bootstrap that genuinely fails is reported, but must not abort setup.
agent_loaded=1 bootstrap_result=1
output="$(start_hyperkey 2>&1)" || fail "a failed bootstrap aborted the setup sequence"
[[ "$output" == *"Bootstrap failed: 5"* ]] || fail "a failed bootstrap hid launchd's own output"
[[ "$output" == *"Warning: could not start"* ]] || fail "a failed bootstrap was not reported"
[[ "$output" == *"Setup continues"* ]] || fail "a failed bootstrap did not say setup still runs"

# Unloading waits for launchd to finish rather than racing the next bootstrap.
agent_loaded=1
stop_hyperkey_process
[[ "$agent_loaded" == 0 ]] || fail "stopping the agent left it loaded"
unset -f hyperkey_launchctl pkill

# Login-service registration, with brew and the process check mocked so no
# service is touched. A bootstrap that loses to an already-running daemon must
# read as the non-problem it is, not as a failed install.
brew_service_result=0
brew() {
  [[ "$*" == "services start herdr" ]] || return 1
  if [[ "$brew_service_result" == 0 ]]; then
    echo "Successfully started \`herdr\`"
    return 0
  fi
  echo "Error: Failure while executing; \`/bin/launchctl bootstrap gui/501 ...\` exited with 5." >&2
  return 1
}
herdr_running=1
pgrep() { [[ "$herdr_running" == 1 ]]; }

brew_service_result=0 herdr_running=0
output="$(ensure_login_service herdr 2>&1)"
[[ "$output" == *"Successfully started"* ]] || fail "a registered login service did not report success"
[[ "$output" != *Error* && "$output" != *Warning* ]] || fail "a successful registration printed an error"

# Already running: explain it, and never show brew's failure or the word Error.
brew_service_result=1 herdr_running=1
output="$(ensure_login_service herdr 2>&1)"
[[ "$output" == *"already running"* ]] || fail "an already-running daemon was not named as the reason"
[[ "$output" == *"not a problem"* ]] || fail "an already-running daemon was not described as harmless"
[[ "$output" != *Error* && "$output" != *Warning* ]] || fail "an already-running daemon was reported as an error"
[[ "$output" != *launchctl* ]] || fail "brew's bootstrap failure leaked into the benign case"

# Not running: the real failure still surfaces, with brew's own output.
brew_service_result=1 herdr_running=0
output="$(ensure_login_service herdr 2>&1)"
[[ "$output" == *"Warning: could not register"* ]] || fail "a real service failure was not reported"
[[ "$output" == *launchctl* ]] || fail "a real service failure hid brew's own output"

# A failure the caller cannot fix must not abort the installation sequence.
brew_service_result=1 herdr_running=0
ensure_login_service herdr >/dev/null 2>&1
unset -f brew pgrep

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
    'reload-config --no-gui') [[ "$(cat "$aerospace_test_state")" == enabled ]] || fail "starting AeroSpace did not re-enable a disabled server" ;;
    *) return 1 ;;
  esac
}
echo enabled > "$aerospace_test_state"
stop_aerospace
[[ -f "$AEROSPACE_DISABLED_MARKER" ]] || fail "stopping AeroSpace left no disabled marker"
[[ "$(cat "$aerospace_test_state")" == disabled ]] || fail "stopping AeroSpace did not disable the server"
start_aerospace
[[ "$(cat "$aerospace_test_state")" == enabled ]]
[[ ! -f "$AEROSPACE_DISABLED_MARKER" ]] || fail "starting AeroSpace left the disabled marker behind"
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
[[ -L "$test_dir/target" ]] || fail "ensure_symlink did not create a symlink"
[[ "$(cat "$test_dir/target")" == default-v1 ]] || fail "ensure_symlink did not install the shipped default"
printf 'default-v2\n' > "$REPO_ROOT/config/example"
ensure_symlink "$REPO_ROOT/config/example" "$test_dir/target" >/dev/null
[[ "$(cat "$test_dir/target")" == default-v2 ]] || fail "an untouched default was not refreshed"
printf 'custom\n' > "$CONF_DIR/example"
ensure_symlink "$REPO_ROOT/config/example" "$test_dir/target" >/dev/null
[[ "$(cat "$test_dir/target")" == custom ]] || fail "a customized config was overwritten by the shipped default"
restore_target "$test_dir/target" "$CONF_DIR/example" >/dev/null
[[ ! -L "$test_dir/target" ]] || fail "restore_target left the symlink in place"
[[ "$(cat "$test_dir/target")" == original ]] || fail "restore_target did not restore the original file"

echo 'PASS: confirmations, cancellation, hyperkey restart, AeroSpace re-enable, config updates, and backup restoration.'
