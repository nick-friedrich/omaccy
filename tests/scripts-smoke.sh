#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/prompts.sh"
source "$REPO_ROOT/scripts/lib/config.sh"
source "$REPO_ROOT/scripts/lib/dependencies.sh"
source "$REPO_ROOT/scripts/lib/git.sh"
source "$REPO_ROOT/scripts/lib/hyperkey.sh"
source "$REPO_ROOT/scripts/lib/fonts.sh"

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

# update.sh describes the code update it is about to perform, offers --no-pull
# for rebuilding the current revision, and rejects anything else. Cancellation
# still happens before the checkout or the network is touched.
output="$(cd "$test_dir"; printf 'n\n' | bash "$REPO_ROOT/scripts/update.sh")"
[[ "$output" == *"Fast-forward this checkout"* ]] || fail "update did not announce the code update"
output="$(cd "$test_dir"; printf 'n\n' | bash "$REPO_ROOT/scripts/update.sh" --no-pull)"
[[ "$output" == *"does not download newer repository code"* ]] || fail "--no-pull did not say the code stays put"
[[ "$output" != *Fast-forward* ]] || fail "--no-pull still announced a code update"
[[ "$output" == *cancelled.* ]] || fail "--no-pull did not honour a declined confirmation"
if (cd "$test_dir"; bash "$REPO_ROOT/scripts/update.sh" --bogus >/dev/null 2>&1); then
  fail "update accepted an unknown flag"
fi

# The combined update question stands in for setup's own: update.sh asks once,
# pulls, then hands off to install, which must not ask again.
output="$(REPO_ROOT="$test_dir" CONF_DIR="$test_dir/config" BAK_DIR="$test_dir/backups" \
  OMACCY_SETUP_CONFIRMED=1 confirm_setup --update </dev/null)"
[[ -z "$output" ]] || fail "an already-confirmed setup prompted a second time"

# Fast-forwarding the checkout, with git mocked so no repository is touched.
# Every refusal must stay non-fatal: setup runs from the present revision.
git_state=clean
git_fetch_result=0
git_ff_result=0
git_head=1111111
# Each assertion captures output in a command substitution, so the mock cannot
# carry a moved HEAD across calls; git_ff_target names where a fast-forward
# lands, and matching git_head is how "already up to date" is expressed.
git_ff_target=2222222
checkout_git() {
  case "$*" in
    'rev-parse --is-inside-work-tree') [[ "$git_state" != not-a-repo ]] ;;
    'symbolic-ref -q HEAD') [[ "$git_state" != detached ]] ;;
    'rev-parse -q --verify @{upstream}') [[ "$git_state" != no-upstream ]] ;;
    'diff --quiet HEAD') [[ "$git_state" != dirty ]] ;;
    'fetch --quiet') return "$git_fetch_result" ;;
    'merge --ff-only --quiet @{upstream}')
      [[ "$git_ff_result" == 0 ]] || return 1
      git_head="$git_ff_target" ;;
    'rev-parse HEAD') echo "$git_head" ;;
    'rev-parse --short '*) echo "$git_head" ;;
    'rev-list --count '*) echo 3 ;;
    *) return 1 ;;
  esac
}

for git_state in not-a-repo detached no-upstream dirty; do
  output="$(update_checkout 2>&1)" || fail "a checkout that cannot be pulled aborted the update"
  [[ "$output" == *"Skipping the code update"* ]] || fail "$git_state did not skip the code update"
  [[ "$output" == *"Setup continues"* ]] || fail "$git_state did not say setup still runs"
  [[ "$output" != *Fetching* ]] || fail "$git_state contacted the remote anyway"
done

git_state=clean git_fetch_result=1
output="$(update_checkout 2>&1)" || fail "an unreachable remote aborted the update"
[[ "$output" == *"could not be reached"* ]] || fail "an unreachable remote was not named as the reason"
[[ "$output" == *"Setup continues"* ]] || fail "an unreachable remote did not say setup still runs"

git_fetch_result=0 git_ff_result=1
output="$(update_checkout 2>&1)" || fail "a diverged branch aborted the update"
[[ "$output" == *"cannot be fast-forwarded"* ]] || fail "a diverged branch was not named as the reason"
[[ "$output" == *"Reconcile it"* ]] || fail "a diverged branch was not told how to recover"
[[ "$output" != *Updated* ]] || fail "a diverged branch was reported as updated"

git_ff_result=0
output="$(update_checkout 2>&1)"
[[ "$output" == *"Updated the checkout to 2222222"* ]] || fail "a fast-forward did not report the new revision"
[[ "$output" == *"3 new commits"* ]] || fail "a fast-forward did not report how far it moved"

git_ff_target="$git_head"
output="$(update_checkout 2>&1)"
[[ "$output" == *"Already on the latest"* ]] || fail "an unchanged checkout was reported as updated"
[[ "$output" != *Updated* ]] || fail "an unchanged checkout claimed to have moved"
unset -f checkout_git

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

# Skew between the continuously-shipped repository and the tag-shipped app.
# The warning exists because a config can land referencing a feature the
# installed binary lacks, which otherwise reads as a broken setting.
OMACCY_DIR="$test_dir/skew"
mkdir -p "$OMACCY_DIR"
skew_count=3
skew_tag_known=0
checkout_git() {
  case "$1" in
    rev-parse) [[ "$skew_tag_known" == 1 ]] ;;
    rev-list) echo "$skew_count" ;;
    *) return 1 ;;
  esac
}

# No recorded release: a locally built app clears the stamp, so there is
# nothing to compare against and nothing to say.
output="$(warn_hyperkey_checkout_skew 2>&1)" || fail "a missing release stamp reported failure"
[[ -z "$output" ]] || fail "a locally built app was warned about"

printf 'v0.3.0' > "$OMACCY_DIR/hyperkey-release"
output="$(warn_hyperkey_checkout_skew 2>&1)" || fail "an unknown tag reported failure"
[[ -z "$output" ]] || fail "a tag absent from the checkout was compared anyway"

skew_tag_known=1
output="$(warn_hyperkey_checkout_skew 2>&1)" || fail "reporting skew returned failure"
[[ "$output" == *"3 app changes newer"* ]] || fail "skew did not report how many app changes are ahead"
[[ "$output" == *"v0.3.0"* ]] || fail "skew did not name the installed release"
[[ "$output" == *"next tagged release"* ]] || fail "skew did not say the changes arrive on their own"
[[ "$output" == *OMACCY_HYPERKEY_BUILD_LOCAL=1* ]] || fail "skew did not offer the local build"

skew_count=1
output="$(warn_hyperkey_checkout_skew 2>&1)"
[[ "$output" == *"1 app change newer"* ]] || fail "a single app change was not singular"

# The common case: the checkout matches the installed release, so stay quiet.
skew_count=0
output="$(warn_hyperkey_checkout_skew 2>&1)" || fail "an in-sync checkout reported failure"
[[ -z "$output" ]] || fail "an in-sync checkout was warned about"

# A checkout with no usable git output must not warn on garbage.
skew_count=not-a-number
output="$(warn_hyperkey_checkout_skew 2>&1)" || fail "unparseable output reported failure"
[[ -z "$output" ]] || fail "unparseable commit count produced a warning"
unset -f checkout_git

# SF Pro, which macOS does not ship and the SketchyBar icons require. Homebrew's
# cask installs a system-domain pkg and would ask for a password, so setup
# expands Apple's image into ~/Library/Fonts as the user instead. Nothing here
# downloads: the checks cover ownership and the never-fatal failure paths.
OMACCY_DIR="$test_dir/fonts"
mkdir -p "$OMACCY_DIR"
sf_pro_home="$test_dir/user-fonts"
mkdir -p "$sf_pro_home"
sf_pro_font_dir() { printf '%s' "$sf_pro_home"; }

# A pre-existing SF Pro, in any domain, is left alone and never claimed.
printf 'font' > "$sf_pro_home/$SF_PRO_FILE"
sf_pro_installed_path() { printf '%s' "$sf_pro_home/$SF_PRO_FILE"; }
output="$(ensure_sf_pro_font 2>&1)" || fail "a pre-existing SF Pro reported failure"
[[ "$output" == *"leave it in place"* ]] || fail "a pre-existing SF Pro was not left alone"
grep -qx "$SF_PRO_FILE" "$OMACCY_DIR/preinstalled-fonts" || fail "a pre-existing SF Pro was not recorded as pre-existing"
[[ ! -f "$OMACCY_DIR/installed-fonts" ]] || fail "a pre-existing SF Pro was claimed as Omaccy-installed"

# Uninstall must not touch a font Omaccy did not install.
output="$(printf 'y\n' | remove_owned_sf_pro_font 2>&1)"
[[ -f "$sf_pro_home/$SF_PRO_FILE" ]] || fail "uninstall removed a pre-existing SF Pro"

# One Omaccy installed is offered for removal and actually goes.
record_dep installed-fonts "$SF_PRO_FILE"
output="$(printf 'n\n' | remove_owned_sf_pro_font 2>&1)"
[[ "$output" == *"Keeping SF Pro"* ]] || fail "declining removal was not honoured"
[[ -f "$sf_pro_home/$SF_PRO_FILE" ]] || fail "declining removal deleted the font anyway"
output="$(printf 'y\n' | remove_owned_sf_pro_font 2>&1)"
[[ "$output" == *"Removed Omaccy-installed"* ]] || fail "accepting removal was not reported"
[[ ! -f "$sf_pro_home/$SF_PRO_FILE" ]] || fail "accepting removal left the font behind"
if grep -qx "$SF_PRO_FILE" "$OMACCY_DIR/installed-fonts" 2>/dev/null; then
  fail "removal left the ownership marker behind"
fi

# An unreachable download must cost the nicer icons and nothing else: the bar
# falls back to Unicode, so this can never abort setup.
sf_pro_installed_path() { return 1; }
curl() { return 1; }
output="$(ensure_sf_pro_font 2>&1)" || fail "an unreachable font download aborted setup"
[[ "$output" == *"Skipping SF Pro"* ]] || fail "a failed download was not reported"
[[ "$output" == *"plain Unicode icons"* ]] || fail "a failed download did not say what happens instead"
if grep -qx "$SF_PRO_FILE" "$OMACCY_DIR/installed-fonts" 2>/dev/null; then
  fail "a failed download claimed ownership anyway"
fi
unset -f curl sf_pro_installed_path sf_pro_font_dir

# The bar's own fallback: every SF Symbol needs a Unicode twin, or a machine
# without SF Pro draws blank gaps -- the bug this all came from.
python3 - "$REPO_ROOT/config/sketchybar/lib/icons.sh" <<'ICONS' || fail "every SF Symbol needs a Unicode twin, or a machine without SF Pro draws blank gaps"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
symbols, fallbacks = text.split("else", 1)
symbols = symbols.split("if sf_pro_available; then", 1)[1]
names = lambda t: {m.group(1) for m in re.finditer(r'^\s*(ICON_[A-Z0-9_]+)=', t, re.M)}
sys.exit(0 if names(symbols) == names(fallbacks) and len(names(symbols)) > 1 else 1)
ICONS
for f in "$REPO_ROOT/config/sketchybar/sketchybarrc" "$REPO_ROOT/config/sketchybar/plugins/battery.sh"; do
  [[ "$(python3 -c "print(sum(1 for c in open('$f',encoding='utf-8').read() if 0xF0000<=ord(c)<=0x10FFFF))")" == 0 ]] \
    || fail "$(basename "$f") still hardcodes SF Symbols instead of using icons.sh"
done

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

echo 'PASS: confirmations, cancellation, checkout fast-forward, hyperkey restart, release skew, SF Pro ownership, AeroSpace re-enable, config updates, and backup restoration.'
