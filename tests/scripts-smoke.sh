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
# --dev installs the checkout as it stands: no pull, and the Hyperkey app built
# from source rather than fetched, the same as OMACCY_HYPERKEY_BUILD_LOCAL=1.
output="$(cd "$test_dir"; printf 'n\n' | bash "$REPO_ROOT/scripts/update.sh" --dev)"
[[ "$output" == *"does not download newer repository code"* ]] || fail "--dev did not say the code stays put"
[[ "$output" != *Fast-forward* ]] || fail "--dev still announced a code update"
[[ "$output" == *"Build Omaccy Hyperkey from this checkout"* ]] || fail "--dev did not say it builds the app locally"
[[ "$output" == *cancelled.* ]] || fail "--dev did not honour a declined confirmation"
output="$(cd "$test_dir"; printf 'n\n' | bash "$REPO_ROOT/scripts/update.sh" --no-pull)"
[[ "$output" != *"Build Omaccy Hyperkey from this checkout"* ]] || fail "--no-pull announced a local app build"
if (cd "$test_dir"; bash "$REPO_ROOT/scripts/update.sh" --bogus >/dev/null 2>&1); then
  fail "update accepted an unknown flag"
fi
if (cd "$test_dir"; bash "$REPO_ROOT/scripts/update.sh" --dev --bogus >/dev/null 2>&1); then
  fail "update accepted an unknown flag after --dev"
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

# The version a locally built app stamps into its bundle, which is what the
# palette and the status item read back. A checkout past its last release must
# not keep reporting that release; without git there is nothing better than the
# checked-in plist to fall back on.
checkout_git() { printf 'v0.4.0-3-gabc1234'; }
[[ "$(hyperkey_source_version)" == "0.4.0-3-gabc1234" ]] \
  || fail "a checkout ahead of its release did not report the distance past it"
checkout_git() { printf 'v0.4.0'; }
[[ "$(hyperkey_source_version)" == "0.4.0" ]] || fail "a checkout on its release tag did not report it plainly"
checkout_git() { return 1; }
[[ "$(hyperkey_source_version)" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$REPO_ROOT/apps/hyperkey/Info.plist")" ]] || fail "an unanswerable git did not fall back to the plist"
unset -f checkout_git


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
[[ "$output" == *"update.sh --dev"* ]] || fail "skew did not offer the local build"

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

# Directory configs (Neovim's) get one link to the canonical directory, with
# each file stamped on its own. The target starts as a link into someone's
# dotfiles repository, which must be moved aside untouched and come back.
mkdir -p "$REPO_ROOT/config/tool/lua" "$test_dir/dotfiles/tool"
printf 'init-v1\n' > "$REPO_ROOT/config/tool/init.lua"
printf 'plug-v1\n' > "$REPO_ROOT/config/tool/lua/plugins.lua"
printf 'mine\n' > "$test_dir/dotfiles/tool/init.lua"
ln -s "$test_dir/dotfiles/tool" "$test_dir/tool-link"
ensure_dir_symlink "$REPO_ROOT/config/tool" "$test_dir/tool-link" >/dev/null
[[ "$(readlink "$test_dir/tool-link")" == "$CONF_DIR/tool" ]] || fail "ensure_dir_symlink did not link the canonical directory"
[[ "$(cat "$test_dir/tool-link/lua/plugins.lua")" == plug-v1 ]] || fail "ensure_dir_symlink did not install nested defaults"
[[ "$(cat "$test_dir/dotfiles/tool/init.lua")" == mine ]] || fail "ensure_dir_symlink wrote through the displaced dotfiles link"
printf 'init-v2\n' > "$REPO_ROOT/config/tool/init.lua"
printf 'plug-v2\n' > "$REPO_ROOT/config/tool/lua/plugins.lua"
printf 'edited\n' > "$CONF_DIR/tool/lua/plugins.lua"
printf 'lock\n' > "$CONF_DIR/tool/lazy-lock.json"
ensure_dir_symlink "$REPO_ROOT/config/tool" "$test_dir/tool-link" >/dev/null
[[ "$(cat "$CONF_DIR/tool/init.lua")" == init-v2 ]] || fail "an untouched file in a directory config was not refreshed"
[[ "$(cat "$CONF_DIR/tool/lua/plugins.lua")" == edited ]] || fail "an edited file in a directory config was overwritten"
[[ "$(cat "$CONF_DIR/tool/lazy-lock.json")" == lock ]] || fail "a generated file in a directory config was disturbed"
restore_target "$test_dir/tool-link" "$CONF_DIR/tool" >/dev/null
[[ "$(readlink "$test_dir/tool-link")" == "$test_dir/dotfiles/tool" ]] || fail "restore_target did not bring back the displaced dotfiles link"

# A real directory, not a link, is backed up and restored whole.
mkdir -p "$test_dir/tool-dir"
printf 'own\n' > "$test_dir/tool-dir/init.lua"
ensure_dir_symlink "$REPO_ROOT/config/tool" "$test_dir/tool-dir" >/dev/null
[[ -L "$test_dir/tool-dir" ]] || fail "ensure_dir_symlink did not replace a real directory with the link"
restore_target "$test_dir/tool-dir" "$CONF_DIR/tool" >/dev/null
[[ ! -L "$test_dir/tool-dir" && "$(cat "$test_dir/tool-dir/init.lua")" == own ]] ||
  fail "restore_target did not restore a displaced directory"

# A shipped directory missing from the checkout must not move the user's aside.
if ensure_dir_symlink "$REPO_ROOT/config/missing" "$test_dir/tool-dir" >/dev/null 2>&1; then
  fail "ensure_dir_symlink accepted a missing shipped directory"
fi
[[ ! -L "$test_dir/tool-dir" && -f "$test_dir/tool-dir/init.lua" ]] ||
  fail "a missing shipped directory still displaced the target"

# Removing the canonical directory keeps it when anything in it was edited,
# and deletes it when only defaults and generated files remain.
remove_canonical_dir tool lazy-lock.json >/dev/null
[[ ! -e "$CONF_DIR/tool" ]] || fail "remove_canonical_dir left an edited directory in place"
[[ "$(cat "$BAK_DIR"/omaccy-tool.*/lua/plugins.lua)" == edited ]] || fail "remove_canonical_dir discarded an edited directory"
[[ ! -e "$OMACCY_DIR/sha256/tool" ]] || fail "remove_canonical_dir left the checksums behind"
rm -rf "$BAK_DIR"/omaccy-tool.*
ensure_dir_symlink "$REPO_ROOT/config/tool" "$test_dir/tool-link" >/dev/null
printf 'lock\n' > "$CONF_DIR/tool/lazy-lock.json"
remove_canonical_dir tool lazy-lock.json >/dev/null
[[ ! -e "$CONF_DIR/tool" ]] || fail "remove_canonical_dir left a pristine directory behind"
if ls -d "$BAK_DIR"/omaccy-tool.* >/dev/null 2>&1; then
  fail "remove_canonical_dir kept a directory holding only defaults and generated files"
fi

# The optional Neovim setup. Homebrew is mocked; the shipped config, the link,
# and uninstall run for real against a temporary HOME. REPO_ROOT is a temporary
# checkout by this point, so the real one is recomputed here.
(
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  source "$repo/scripts/lib/neovim.sh"
  REPO_ROOT="$repo"
  HOME="$test_dir/nvim-home"
  OMACCY_DIR="$test_dir/nvim-state"
  CONF_DIR="$OMACCY_DIR/config"
  BAK_DIR="$OMACCY_DIR/backups"
  mkdir -p "$HOME/.config/nvim" "$BAK_DIR"
  printf 'own\n' > "$HOME/.config/nvim/init.lua"
  calls="$test_dir/nvim-calls"
  : > "$calls"
  ensure_formula() { printf 'formula %s\n' "$1" >> "$calls"; }

  # Declining is remembered, so an update does not ask again, and installs nothing.
  output="$(printf 'n\n' | decide_neovim_setup)"
  [[ "$output" == *"[y/N]"* ]] || fail "the Neovim setup was not asked about"
  [[ "$output" == *"Moves your current ~/.config/nvim"* ]] || fail "the Neovim question did not say the existing config moves"
  [[ "$(cat "$OMACCY_DIR/neovim")" == off ]] || fail "declining Neovim was not remembered"
  output="$(decide_neovim_setup </dev/null)"
  [[ -z "$output" ]] || fail "a remembered Neovim answer was asked again"
  install_neovim >/dev/null
  [[ ! -s "$calls" ]] || fail "a declined Neovim setup still installed something"
  [[ ! -L "$HOME/.config/nvim" ]] || fail "a declined Neovim setup still linked the config"

  # An unattended run never opts in, and leaves the question for the user.
  rm "$OMACCY_DIR/neovim"
  output="$(OMACCY_ASSUME_YES=1 decide_neovim_setup </dev/null)"
  [[ "$output" == *"Skipping the optional Neovim setup"* ]] || fail "OMACCY_ASSUME_YES did not say it skipped Neovim"
  [[ "$output" != *"[y/N]"* ]] || fail "OMACCY_ASSUME_YES answered the Neovim question"
  [[ ! -e "$OMACCY_DIR/neovim" ]] || fail "OMACCY_ASSUME_YES recorded a Neovim answer"

  # Accepting installs Neovim and puts Omaccy's config at ~/.config/nvim.
  printf 'y\n' | decide_neovim_setup >/dev/null
  install_neovim >/dev/null
  grep -qx 'formula neovim' "$calls" || fail "an accepted Neovim setup did not install Neovim"
  grep -qx 'formula ripgrep' "$calls" || fail "an accepted Neovim setup did not install ripgrep"
  [[ "$(readlink "$HOME/.config/nvim")" == "$CONF_DIR/nvim" ]] || fail "~/.config/nvim was not linked to Omaccy's config"
  cmp -s "$HOME/.config/nvim/lua/lazy_setup.lua" "$repo/config/nvim/lua/lazy_setup.lua" ||
    fail "the linked Neovim config is not the shipped one"
  [[ -f "$HOME/.config/nvim/.stylua.toml" ]] || fail "the Neovim config lost its dotfiles"

  # Uninstall brings the user's config back and clears Omaccy's state.
  printf 'lock\n' > "$CONF_DIR/nvim/lazy-lock.json"
  uninstall_neovim_config >/dev/null
  [[ ! -L "$HOME/.config/nvim" && "$(cat "$HOME/.config/nvim/init.lua")" == own ]] ||
    fail "uninstall did not restore the user's Neovim config"
  [[ ! -e "$CONF_DIR/nvim" ]] || fail "uninstall left an unedited Neovim config behind"
  [[ ! -e "$OMACCY_DIR/neovim" ]] || fail "uninstall left the Neovim answer behind"
)

# The retired master/stack placement. HOME is overridden inside a subshell
# because the function reads the real ~/.config path the installer wrote to;
# `set -e` still aborts the run when the subshell fails.
(
  HOME="$test_dir/retire-home"
  OMACCY_DIR="$test_dir/retire-state"
  CONF_DIR="$OMACCY_DIR/config"
  mkdir -p "$HOME/.config/aerospace" "$CONF_DIR/aerospace" "$OMACCY_DIR/sha256/aerospace"
  printf 'placement\n' > "$CONF_DIR/aerospace/master-stack.sh"
  printf 'sum\n' > "$OMACCY_DIR/sha256/aerospace/master-stack.sh"
  ln -s "$CONF_DIR/aerospace/master-stack.sh" "$HOME/.config/aerospace/master-stack.sh"
  retire_master_stack_script >/dev/null
  [[ ! -L "$HOME/.config/aerospace/master-stack.sh" ]] ||
    fail "retire_master_stack_script left the symlink AeroSpace would still run"
  [[ ! -e "$CONF_DIR/aerospace/master-stack.sh" ]] ||
    fail "retire_master_stack_script left the canonical copy behind"
  [[ ! -e "$OMACCY_DIR/sha256/aerospace/master-stack.sh" ]] ||
    fail "retire_master_stack_script left the checksum behind"

  # A real file at that path is the user's, not a link Omaccy made.
  printf 'mine\n' > "$HOME/.config/aerospace/master-stack.sh"
  retire_master_stack_script >/dev/null
  [[ "$(cat "$HOME/.config/aerospace/master-stack.sh")" == mine ]] ||
    fail "retire_master_stack_script removed a file it did not install"

  # An edited canonical copy is kept rather than discarded with the feature.
  BAK_DIR="$OMACCY_DIR/backups"
  printf 'edited\n' > "$CONF_DIR/aerospace/master-stack.sh"
  retire_master_stack_script >/dev/null
  [[ ! -e "$CONF_DIR/aerospace/master-stack.sh" ]] ||
    fail "retire_master_stack_script left an edited canonical copy in place"
  [[ "$(cat "$BAK_DIR"/master-stack.sh.*)" == edited ]] ||
    fail "retire_master_stack_script discarded an edited canonical copy"
)

# Per-workspace layout modes, against a fake aerospace that records what it was
# asked to do. HOME is overridden because the store is ~/.omaccy/workspace-layout
# by design -- the bar and the AeroSpace callback both find it without being
# told where it is. REPO_ROOT is a temporary checkout by this point, so the real
# one is recomputed here.
(
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  layout="$repo/config/aerospace/layout.sh"
  HOME="$test_dir/layout-home"
  mkdir -p "$HOME"
  AEROSPACE_LOG="$test_dir/layout-calls.log"
  export AEROSPACE_LOG
  fake_aerospace="$test_dir/layout-bin/aerospace"
  mkdir -p "$(dirname "$fake_aerospace")"
  cat > "$fake_aerospace" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AEROSPACE_LOG"
case "$1" in
  list-workspaces) printf '3\n' ;;
  list-windows)
    case "$*" in
      *--count*) printf '2\n' ;;
      *workspace-root-container-layout*) printf 'h_tiles\n' ;;
    esac
    ;;
esac
FAKE
  chmod +x "$fake_aerospace"
  export AEROSPACE_BIN="$fake_aerospace"

  [[ "$(bash "$layout" current 3)" == horizontal ]] ||
    fail "layout.sh did not fall back to the default mode"

  bash "$layout" set vertical 3 >/dev/null ||
    fail "layout.sh could not set a mode"
  [[ "$(bash "$layout" current 3)" == vertical ]] ||
    fail "layout.sh did not read back the mode it stored"
  [[ "$(bash "$layout" label 3)" == Rows ]] ||
    fail "layout.sh labelled the vertical mode wrongly"
  [[ "$(bash "$layout" current 4)" == horizontal ]] ||
    fail "a mode set on one workspace leaked into another"

  if bash "$layout" set sideways 3 >/dev/null 2>&1; then
    fail "layout.sh accepted a mode that does not exist"
  fi
  [[ "$(bash "$layout" current 3)" == vertical ]] ||
    fail "a rejected mode still overwrote the stored one"

  printf 'garbage\n' > "$HOME/.omaccy/workspace-layout/3"
  [[ "$(bash "$layout" current 3)" == horizontal ]] ||
    fail "a damaged store was not replaced by the default"

  # Recursive is the mode that means "leave the tree alone", so re-asserting it
  # has to issue nothing at all.
  bash "$layout" set recursive 3 >/dev/null
  : > "$AEROSPACE_LOG"
  bash "$layout" apply 3 >/dev/null
  if grep -q . "$AEROSPACE_LOG"; then
    fail "applying the recursive mode drove AeroSpace instead of leaving it alone"
  fi

  # A flat workspace stays flat by itself, so re-asserting a mode whose root
  # already matches must not touch the layout either -- that is what keeps this
  # from overwriting sizes on every new window.
  bash "$layout" set horizontal 3 >/dev/null
  : > "$AEROSPACE_LOG"
  bash "$layout" apply 3 >/dev/null
  if grep -q '^layout ' "$AEROSPACE_LOG"; then
    fail "re-asserting an unchanged mode reset the workspace layout"
  fi
)

# The calendar popup, against a sketchybar that records one argument per line.
# HOME is temporary so the palette falls back to its Catppuccin defaults and the
# accent color is known; today and the first weekday are pinned so the grid is.
(
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  HOME="$test_dir/calendar-home"
  mkdir -p "$HOME"
  trace="$test_dir/calendar-trace"
  recorder="$test_dir/calendar-bin/sketchybar"
  mkdir -p "$(dirname "$recorder")"
  cat > "$recorder" <<'FAKE'
#!/usr/bin/env bash
for argument in "$@"; do printf '%s\n' "$argument"; done >> "$CALENDAR_TRACE"
FAKE
  chmod +x "$recorder"
  calendar() {
    : > "$trace"
    CALENDAR_TRACE="$trace" OMACCY_SKETCHYBAR_BIN="$recorder" \
      OMACCY_STATE_DIR="$test_dir/calendar-state" \
      OMACCY_CALENDAR_TODAY="$1" OMACCY_FIRST_WEEKDAY="$2" \
      /bin/bash "$repo/config/sketchybar/plugins/calendar.sh" "$3"
  }

  # September 2026 starts on a Tuesday and has five weeks.
  calendar 2026-09-11 1 click
  grep -Fxq 'label=September 2026' "$trace" || fail "the calendar did not name the month"
  grep -Fxq 'label= Mo  Tu  We  Th  Fr  Sa  Su ' "$trace" ||
    fail "a Monday-first calendar did not start its week on Monday"
  grep -Fxq 'label=      1   2   3   4   5   6 ' "$trace" ||
    fail "the first of the month was not placed under its weekday"
  grep -Fxq 'label=  7   8   9  10 [11] 12  13 ' "$trace" ||
    fail "today was not bracketed in place"
  [[ "$(awk 'found { print; exit } index($0, "[11]") { found = 1 }' "$trace")" == "label.color=0xff89b4fa" ]] ||
    fail "the week holding today was not drawn in the accent color"
  grep -Fxq 'label= 28  29  30 ' "$trace" || fail "the month's last days were dropped"
  [[ "$(awk '$0 == "clock.week6" { getline; print; exit }' "$trace")" == "drawing=off" ]] ||
    fail "an unused sixth week row was left showing"
  grep -Fxq 'popup.drawing=toggle' "$trace" || fail "clicking the date did not open the popup"
  # SketchyBar sizes a label without its leading whitespace but still draws it,
  # so a week starting mid-row is clipped unless its width is fixed. The trace
  # cannot show that, so check the bar config keeps the width on both the
  # weekday row and the week rows.
  [[ "$(grep -cF 'label.width="$CALENDAR_WIDTH"' "$repo/config/sketchybar/sketchybarrc")" -ge 2 ]] ||
    fail "the calendar grid rows lost their fixed width, so short weeks are clipped"

  # February 2026 begins on a Sunday, so a Sunday-first grid has no blanks.
  calendar 2026-02-01 7 click
  grep -Fxq 'label= Su  Mo  Tu  We  Th  Fr  Sa ' "$trace" ||
    fail "a Sunday-first calendar did not start its week on Sunday"
  grep -Fxq 'label=[ 1]  2   3   4   5   6   7 ' "$trace" ||
    fail "a month starting on the first weekday gained leading blanks"

  # Paging crosses the year, and clicking the date again starts from today.
  calendar 2026-12-31 1 click
  calendar 2026-12-31 1 next
  grep -Fxq 'label=January 2027' "$trace" || fail "next month did not cross into the new year"
  if grep -q '\[' "$trace"; then
    fail "today was bracketed in a month it does not fall in"
  fi
  calendar 2026-12-31 1 click
  grep -Fxq 'label=December 2026' "$trace" || fail "reopening the calendar kept the paged month"

  printf 'sideways\n' > "$test_dir/calendar-state/calendar-offset"
  calendar 2026-12-31 1 next
  grep -Fxq 'label=January 2027' "$trace" || fail "a damaged page offset was not read as today"
)

# The Apple menu, against recording stand-ins for every command it would run,
# so no test ever sleeps, restarts or logs out the machine it runs on.
(
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  calls="$test_dir/apple-menu-calls"
  bin="$test_dir/apple-menu-bin"
  mkdir -p "$bin"
  for tool in sketchybar open osascript pmset menu-toggle; do
    cat > "$bin/$tool" <<FAKE
#!/usr/bin/env bash
printf '%s %s\n' "$tool" "\$*" >> "$calls"
FAKE
    chmod +x "$bin/$tool"
  done
  apple_menu() {
    : > "$calls"
    OMACCY_SKETCHYBAR_BIN="$bin/sketchybar" OMACCY_OPEN_BIN="$bin/open" \
      OMACCY_OSASCRIPT_BIN="$bin/osascript" OMACCY_PMSET_BIN="$bin/pmset" \
      OMACCY_MENU_TOGGLE="$bin/menu-toggle" \
      /bin/bash "$repo/config/sketchybar/plugins/apple-menu.sh" "$1"
  }

  apple_menu click
  grep -Fxq 'sketchybar --set native_menu popup.drawing=toggle' "$calls" ||
    fail "clicking the Apple logo did not open its menu"

  apple_menu omaccy-settings
  grep -Fxq 'open omaccy://settings' "$calls" ||
    fail "Omaccy Settings did not open the launcher's Settings page"
  grep -Fxq 'sketchybar --set native_menu popup.drawing=off' "$calls" ||
    fail "choosing a row left the Apple menu open"

  apple_menu system-settings
  grep -Fxq 'open -b com.apple.systempreferences' "$calls" || fail "System Settings did not open"

  apple_menu sleep
  grep -Fxq 'pmset sleepnow' "$calls" || fail "Sleep did not put the Mac to sleep"

  # Each of these has to ask first, with the dialog macOS itself shows. The
  # unconfirmed events (rest, shut, rlgo) must never be what goes out.
  for pair in restart:rrst shutdown:rsdn logout:logo; do
    apple_menu "${pair%%:*}"
    grep -q "loginwindow.*aevt${pair##*:}" "$calls" ||
      fail "${pair%%:*} did not ask loginwindow with its confirmation dialog"
    if grep -Eq 'aevt(rest|shut|rlgo)' "$calls"; then
      fail "${pair%%:*} sent the event that skips the confirmation"
    fi
  done

  apple_menu hide-bar
  grep -q '^menu-toggle' "$calls" || fail "Hide SketchyBar did not hand over to the macOS menu bar"

  if apple_menu nonsense 2>/dev/null; then
    fail "the Apple menu accepted an action it does not have"
  fi
)

# The front app's menus, with osascript replaced by one that answers the way
# System Events does -- or refuses, as it does before SketchyBar has
# Accessibility -- so no test reads or opens a real app's menus.
(
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  plugin="$repo/config/sketchybar/plugins/front-app.sh"
  calls="$test_dir/front-app-calls"
  bin="$test_dir/front-app-bin"
  denied="$test_dir/front-app-denied"
  mkdir -p "$bin"
  for tool in sketchybar open; do
    cat > "$bin/$tool" <<FAKE
#!/usr/bin/env bash
printf '%s %s\n' "$tool" "\$*" >> "$calls"
FAKE
    chmod +x "$bin/$tool"
  done
  # Reading the menus is a script on stdin; opening one is a script in -e.
  cat > "$bin/osascript" <<FAKE
#!/usr/bin/env bash
if [[ \$# -gt 0 ]]; then
  printf 'osascript %s\n' "\$*" >> "$calls"
  exit 0
fi
cat > /dev/null
[[ -f "$denied" ]] && exit 1
printf '4242\nApple\nGhostty\nFile\n\nmissing value\nEdit\nWindow\n'
FAKE
  chmod +x "$bin/osascript"
  front_app() {
    : > "$calls"
    OMACCY_SKETCHYBAR_BIN="$bin/sketchybar" OMACCY_OPEN_BIN="$bin/open" \
      OMACCY_OSASCRIPT_BIN="$bin/osascript" \
      /bin/bash "$plugin" "$@"
  }

  front_app click
  grep -Fq "front_app.menu.1 label=Ghostty drawing=on click_script='$plugin' open 4242 2 " "$calls" ||
    fail "the app's own menu was not the first row"
  # Untitled items are skipped, but each row still opens the menu at its own
  # position in the bar, not at its row number.
  grep -Fq "front_app.menu.3 label=Edit drawing=on click_script='$plugin' open 4242 6 " "$calls" ||
    fail "a menu after an untitled one opened the wrong menu"
  grep -Fq 'front_app.menu.5 drawing=off' "$calls" || fail "rows past the app's last menu stayed visible"
  grep -Fq 'front_app.menu.16 drawing=off' "$calls" || fail "the last popup row was not hidden"
  if grep -Eq 'label=(Apple|missing value)' "$calls"; then
    fail "the Apple menu or an untitled item was listed"
  fi
  grep -Fxq 'sketchybar --set front_app popup.drawing=toggle' "$calls" ||
    fail "clicking the app name did not open its menus"

  front_app open 4242 6
  grep -Fq 'click menu bar item 6 of menu bar 1 of (first application process whose unix id is 4242)' "$calls" ||
    fail "choosing a menu did not open it in the app it was read from"
  grep -Fxq 'sketchybar --set front_app popup.drawing=off' "$calls" ||
    fail "choosing a menu left the popup open"

  if front_app open '4242) to quit' 6 2>/dev/null || grep -q '^osascript' "$calls"; then
    fail "a row that is not a pid and a position reached AppleScript"
  fi

  : > "$denied"
  front_app click
  grep -Fq "front_app.menu.1 label=Allow SketchyBar in Accessibility… drawing=on click_script='$plugin' accessibility " "$calls" ||
    fail "without Accessibility the popup did not say what to allow"
  grep -Fq 'front_app.menu.2 drawing=off' "$calls" || fail "without Accessibility other rows stayed visible"
  rm -f "$denied"

  front_app accessibility
  grep -Fxq 'open x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility' "$calls" ||
    fail "the Accessibility row did not open Privacy & Security"

  : > "$calls"
  INFO=Safari OMACCY_SKETCHYBAR_BIN="$bin/sketchybar" OMACCY_OSASCRIPT_BIN="$bin/osascript" \
    /bin/bash "$plugin"
  grep -Fxq 'sketchybar --set front_app label=Safari popup.drawing=off' "$calls" ||
    fail "switching apps did not rename the item and close the last app's menus"
)

# The battery popup, with pmset replaced by a script that answers the way pmset
# does, so every charge state can be shown and nothing actually sleeps.
(
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  HOME="$test_dir/battery-home"
  mkdir -p "$HOME"
  calls="$test_dir/battery-calls"
  bin="$test_dir/battery-bin"
  mkdir -p "$bin"
  cat > "$bin/pmset" <<'FAKE'
#!/usr/bin/env bash
printf 'pmset %s\n' "$*" >> "$BATTERY_CALLS"
case "$*" in
  "-g batt")
    printf "Now drawing from '%s'\n -InternalBattery-0 (id=1)\t%s present: true\n" \
      "$BATTERY_SOURCE" "$BATTERY_LINE"
    ;;
  "-g") printf ' lowpowermode         %s\n' "$BATTERY_LOW_POWER" ;;
esac
FAKE
  for tool in sketchybar open; do
    cat > "$bin/$tool" <<FAKE
#!/usr/bin/env bash
printf '%s %s\n' "$tool" "\$*" >> "$calls"
FAKE
  done
  chmod +x "$bin"/*
  battery() {
    : > "$calls"
    BATTERY_CALLS="$calls" BATTERY_SOURCE="$2" BATTERY_LINE="$3" BATTERY_LOW_POWER="$4" \
      OMACCY_SKETCHYBAR_BIN="$bin/sketchybar" OMACCY_PMSET_BIN="$bin/pmset" \
      OMACCY_OPEN_BIN="$bin/open" OMACCY_STATE_DIR="$test_dir/battery-state" \
      /bin/bash "$repo/config/sketchybar/plugins/battery.sh" "$1"
  }

  battery click 'Battery Power' '100%; discharging; 8:17 remaining' 0
  grep -qF 'battery.status label=100% · 8:17 remaining' "$calls" ||
    fail "the battery popup did not say how long the charge will last"
  grep -qF 'battery.lowpower label=Low Power Mode · Off' "$calls" ||
    fail "the battery popup misread Low Power Mode as on"
  grep -qF 'caffeinate.off drawing=off' "$calls" ||
    fail "the battery popup offered to turn off a keep-awake that is not running"
  grep -qF -- '--set battery popup.drawing=toggle' "$calls" ||
    fail "clicking the battery did not open its popup"

  battery click 'AC Power' '64%; charging; 1:02 remaining' 1
  grep -qF 'label=64% · Charging · 1:02 until full' "$calls" ||
    fail "a charging battery was not described as charging"
  grep -qF 'label=Low Power Mode · On' "$calls" || fail "the battery popup missed Low Power Mode being on"

  battery click 'AC Power' '100%; charged; 0:00 remaining' 0
  grep -qF 'label=100% · Fully charged' "$calls" || fail "a full battery was not described as charged"

  battery display-sleep 'Battery Power' '100%; discharging; 8:17 remaining' 0
  grep -Fxq 'pmset displaysleepnow' "$calls" || fail "turning the display off did not reach pmset"

  battery settings 'Battery Power' '100%; discharging; 8:17 remaining' 0
  grep -Fxq 'open x-apple.systempreferences:com.apple.Battery-Settings.extension' "$calls" ||
    fail "Battery Settings did not open the Battery pane"
)

# Keep-awake state. The fake caffeinate stands in for the real one through
# OMACCY_CAFFEINATE_BIN; it sleeps so the process is genuinely alive, and it is
# invoked by absolute path so `ps -o command=` shows a path the identity check
# can match. `ps -o comm=` would report the interpreter for a script, which is
# why the library reads the full command line instead.
caffeinate_test_dir="$test_dir/caffeinate"
mkdir -p "$caffeinate_test_dir"
fake_caffeinate="$caffeinate_test_dir/caffeinate"
# Sleeping in short steps rather than one long call so that killing this
# process, as the process-group test does, does not orphan a child that
# outlives the run.
cat > "$fake_caffeinate" <<'FAKE'
#!/usr/bin/env bash
while :; do sleep 1; done
FAKE
chmod +x "$fake_caffeinate"

OMACCY_STATE_DIR="$caffeinate_test_dir/state"
OMACCY_CAFFEINATE_BIN="$fake_caffeinate"
# REPO_ROOT was repointed at a temporary checkout above, so resolve the real
# one from this file rather than reusing it.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/sketchybar/lib/caffeinate-state.sh"

caffeinate_test_cleanup() {
  pkill -f "$fake_caffeinate" 2>/dev/null || true
}
trap 'caffeinate_test_cleanup; rm -rf "$test_dir"' EXIT

caffeinate_start 0
caffeinate_pid="$(caffeinate_read_file "$CAFFEINATE_PID_FILE")" \
  || fail "starting keep-awake recorded no pid"
caffeinate_is_active || fail "a just-started keep-awake did not report as active"
[[ "$(caffeinate_remaining)" == 0 ]] || fail "an indefinite session did not report an open-ended deadline"
[[ "$(caffeinate_label "$(caffeinate_remaining)")" == On ]] || fail "an indefinite session was not labelled On"

# The whole point of the change: caffeinate must not sit in the process group
# of whatever launched it, because launchd ends that entire group when the
# SketchyBar service is restarted -- which scripts/theme.sh and scripts/font.sh
# both do for an ordinary theme or font switch.
caffeinate_pgid="$(ps -o pgid= -p "$caffeinate_pid" | tr -d ' ')"
shell_pgid="$(ps -o pgid= -p $$ | tr -d ' ')"
[[ "$caffeinate_pgid" != "$shell_pgid" ]] \
  || fail "keep-awake shares its launcher's process group and dies with the service"
[[ "$caffeinate_pgid" == "$caffeinate_pid" ]] \
  || fail "keep-awake did not lead a process group of its own"

# Losing the process the way a service restart does must not lose the session:
# the deadline is the state, the pid only a cache of who is serving it.
kill "$caffeinate_pid" 2>/dev/null || true
while kill -0 "$caffeinate_pid" 2>/dev/null; do :; done
if caffeinate_is_active; then
  echo 'FAIL: a killed keep-awake still reported as active' >&2
  exit 1
fi
caffeinate_ensure_running || fail "keep-awake did not come back after its process was killed"
caffeinate_revived_pid="$(caffeinate_read_file "$CAFFEINATE_PID_FILE")"
[[ "$caffeinate_revived_pid" != "$caffeinate_pid" ]] || fail "reviving keep-awake reused the dead pid"
caffeinate_is_active || fail "the revived keep-awake did not report as active"
caffeinate_stop

# A recorded pid that has been reused by an unrelated process is not keep-awake.
# `kill -0` alone would accept it, leaving the bar claiming On while the display
# sleeps -- and would have uninstall signal a stranger.
sleep 120 >/dev/null 2>&1 &
caffeinate_impostor_pid=$!
disown "$caffeinate_impostor_pid" 2>/dev/null || true
printf '%s\n' "$caffeinate_impostor_pid" > "$CAFFEINATE_PID_FILE"
if caffeinate_is_active; then
  echo 'FAIL: an unrelated process holding a reused pid was accepted as keep-awake' >&2
  exit 1
fi
caffeinate_stop
kill -0 "$caffeinate_impostor_pid" 2>/dev/null \
  || fail "stopping keep-awake signalled an unrelated process holding a reused pid"
kill "$caffeinate_impostor_pid" 2>/dev/null || true
[[ ! -f "$CAFFEINATE_END_FILE" ]] || fail "stopping keep-awake left its deadline behind"

# Resume is scoped to the current boot. Reviving a session through a service
# restart is the fix; silently reviving an indefinite one after a reboot is not.
caffeinate_start 0
caffeinate_pid="$(caffeinate_read_file "$CAFFEINATE_PID_FILE")"
kill "$caffeinate_pid" 2>/dev/null || true
printf '%s\n' "$(( $(caffeinate_boot_id) - 1 ))" > "$CAFFEINATE_BOOT_FILE"
if caffeinate_remaining >/dev/null; then
  echo 'FAIL: state recorded under an earlier boot was treated as current' >&2
  exit 1
fi
[[ ! -f "$CAFFEINATE_PID_FILE" ]] || fail "stale state from an earlier boot was not discarded"

# State written before this version has no boot stamp at all, and describes a
# process that cannot still be ours.
mkdir -p "$OMACCY_STATE_DIR"
printf '0\n' > "$CAFFEINATE_END_FILE"
printf '1\n' > "$CAFFEINATE_PID_FILE"
if caffeinate_remaining >/dev/null; then
  echo 'FAIL: pre-upgrade state without a boot stamp was treated as current' >&2
  exit 1
fi

# A timed session counts down, and is over once its deadline passes.
caffeinate_start 3600
caffeinate_remaining_seconds="$(caffeinate_remaining)" || fail "a timed session reported no time left"
[[ "$caffeinate_remaining_seconds" -gt 3500 && "$caffeinate_remaining_seconds" -le 3600 ]] \
  || fail "a one-hour session reported $caffeinate_remaining_seconds seconds left"
[[ "$(caffeinate_label 3600)" == 1h ]] || fail "an hour was not labelled 1h"
[[ "$(caffeinate_label 5400)" == "1h 30m" ]] || fail "ninety minutes was not labelled 1h 30m"
[[ "$(caffeinate_label 1)" == 1m ]] || fail "a partial minute rounded down to a finished session"
cat "$CAFFEINATE_PID_FILE" > "$caffeinate_test_dir/timed-pid"
printf '%s\n' "$(( $(date +%s) - 1 ))" > "$CAFFEINATE_END_FILE"
if caffeinate_remaining >/dev/null; then
  echo 'FAIL: a session past its deadline still reported time left' >&2
  exit 1
fi
[[ ! -f "$CAFFEINATE_PID_FILE" ]] || fail "an expired session left its state behind"
if caffeinate_process_alive "$(cat "$caffeinate_test_dir/timed-pid")"; then
  echo 'FAIL: an expired session left its process running with no pid left to stop it by' >&2
  exit 1
fi
caffeinate_stop

# The plugin is the only caller that reconciles on a timer, so drive it through
# its real entry points with a recording sketchybar. This is what a SketchyBar
# restart looks like from the bar's side: the process is gone, the next tick
# runs, and the item has to come back on rather than report keep-awake as off.
caffeinate_bar_trace="$caffeinate_test_dir/bar-trace"
fake_sketchybar="$caffeinate_test_dir/sketchybar"
cat > "$fake_sketchybar" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$OMACCY_BAR_TRACE"
FAKE
chmod +x "$fake_sketchybar"

caffeinate_plugin() {
  OMACCY_BAR_TRACE="$caffeinate_bar_trace" \
  OMACCY_STATE_DIR="$OMACCY_STATE_DIR" \
  OMACCY_CAFFEINATE_BIN="$OMACCY_CAFFEINATE_BIN" \
  OMACCY_SKETCHYBAR_BIN="$fake_sketchybar" \
    /bin/bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/sketchybar/plugins/caffeinate.sh" "$@"
}

: > "$caffeinate_bar_trace"
caffeinate_plugin start 1800
grep -q 'label.drawing=on' "$caffeinate_bar_trace" || fail "starting keep-awake did not light the bar item"
grep -q 'label=30m' "$caffeinate_bar_trace" || fail "a thirty-minute session was not shown as 30m"
grep -qE '(^| )drawing=on( |$)' "$caffeinate_bar_trace" \
  || fail "starting keep-awake did not put its item back in the bar"
grep -qF -- '--set battery popup.drawing=off' "$caffeinate_bar_trace" \
  || fail "starting keep-awake from the battery popup left the popup open"
caffeinate_plugin_pid="$(caffeinate_read_file "$CAFFEINATE_PID_FILE")" \
  || fail "the plugin recorded no pid"

kill "$caffeinate_plugin_pid" 2>/dev/null || true
while kill -0 "$caffeinate_plugin_pid" 2>/dev/null; do :; done
: > "$caffeinate_bar_trace"
caffeinate_plugin update
grep -q 'label.drawing=on' "$caffeinate_bar_trace" \
  || fail "a tick after the process died reported keep-awake as off instead of restoring it"
caffeinate_plugin_revived="$(caffeinate_read_file "$CAFFEINATE_PID_FILE")"
[[ "$caffeinate_plugin_revived" != "$caffeinate_plugin_pid" ]] \
  || fail "the plugin did not relaunch keep-awake after its process died"
caffeinate_process_alive "$caffeinate_plugin_revived" \
  || fail "the pid the plugin recorded is not a running keep-awake"

: > "$caffeinate_bar_trace"
caffeinate_plugin stop
grep -q 'label.drawing=off' "$caffeinate_bar_trace" || fail "stopping keep-awake did not dim the bar item"
grep -qE '(^| )drawing=off( |$)' "$caffeinate_bar_trace" \
  || fail "stopping keep-awake left its item in the bar"
if caffeinate_process_alive "$caffeinate_plugin_revived"; then
  echo 'FAIL: stopping keep-awake through the plugin left the process running' >&2
  exit 1
fi
[[ ! -f "$CAFFEINATE_END_FILE" ]] || fail "stopping keep-awake through the plugin left its deadline behind"

# Neovim follows the theme on its own by watching ~/.omaccy, so check that
# every shipped theme names a colorscheme, and that a running nvim repaints
# when the theme changes. Built-in colorschemes stand in for the plugins, so
# nothing downloads; the repaint check is skipped where nvim is not installed.
nvim_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for theme_file in "$nvim_repo"/config/sketchybar/themes/*.sh; do
  grep -Eq '^NVIM_COLORSCHEME="[^"]+"' "$theme_file" ||
    fail "$(basename "$theme_file") names no Neovim colorscheme"
done

# herdr follows the theme through the name in its config.toml, so every shipped
# theme has to name one herdr actually has. `herdr config check` reads the
# config under $HOME, so a scratch home keeps the real one out of it.
# herdr's terminal theme draws the active tab's number in ANSI dark gray on the
# accent unless panel_bg is set -- unreadable on Everforest and GitHub Dark --
# so a palette on it has to name its panel color.
source "$nvim_repo/scripts/lib/herdr-settings.sh"
herdr_config="$test_dir/herdr-home/.config/herdr/config.toml"
mkdir -p "$(dirname "$herdr_config")"
for theme_file in "$nvim_repo"/config/sketchybar/themes/*.sh; do
  herdr_theme="$(sed -n 's/^HERDR_THEME="\([^"]*\)".*/\1/p' "$theme_file")"
  herdr_accent="$(sed -n 's/^HERDR_ACCENT="\([^"]*\)".*/\1/p' "$theme_file")"
  herdr_panel_bg="$(sed -n 's/^HERDR_PANEL_BG="\([^"]*\)".*/\1/p' "$theme_file")"
  [[ -n "$herdr_theme" ]] || fail "$(basename "$theme_file") names no herdr theme"
  [[ "$herdr_theme" != terminal || -n "$herdr_panel_bg" ]] ||
    fail "$(basename "$theme_file") puts herdr on its terminal theme without HERDR_PANEL_BG"
  if command -v herdr >/dev/null 2>&1; then
    : > "$herdr_config"
    herdr_config_with_theme "$herdr_config" "$herdr_theme" "$herdr_accent" "$herdr_panel_bg" > "$herdr_config.new"
    mv "$herdr_config.new" "$herdr_config"
    [[ "$(HOME="$test_dir/herdr-home" herdr config check 2>&1)" == "config: ok" ]] ||
      fail "herdr rejects the config written for $(basename "$theme_file")"
  fi
done
if command -v nvim >/dev/null 2>&1; then
  nvim_home="$test_dir/nvim-omaccy"
  mkdir -p "$nvim_home/config/sketchybar/themes"
  printf 'NVIM_COLORSCHEME="desert"\nAPPEARANCE="dark"\n' > "$nvim_home/config/sketchybar/themes/first.sh"
  printf 'NVIM_COLORSCHEME="morning"\nAPPEARANCE="light"\n' > "$nvim_home/config/sketchybar/themes/second.sh"
  printf 'first\n' > "$nvim_home/theme"
  cat > "$test_dir/nvim-theme.lua" <<'LUA'
vim.opt.rtp:prepend(vim.env.OMACCY_TEST_NVIM_CONFIG)
local theme = require "omaccy.theme"
theme.apply()
if vim.g.colors_name ~= "desert" or vim.o.background ~= "dark" then
  io.stderr:write "FAIL: nvim did not start in the theme's colorscheme\n"
  os.exit(1)
end
theme.watch()
local file = assert(io.open(vim.env.OMACCY_DIR .. "/theme", "w"))
file:write "second\n"
file:close()
local repainted = vim.wait(5000, function()
  return vim.g.colors_name == "morning" and vim.o.background == "light"
end, 20)
if not repainted then
  io.stderr:write "FAIL: a running nvim did not repaint when the theme changed\n"
  os.exit(1)
end
LUA
  OMACCY_DIR="$nvim_home" OMACCY_TEST_NVIM_CONFIG="$nvim_repo/config/nvim" \
    nvim --headless -u NONE -i NONE -l "$test_dir/nvim-theme.lua" ||
    fail "Neovim did not follow the theme"
fi

echo 'PASS: confirmations, cancellation, checkout fast-forward, hyperkey restart, build version, release skew, SF Pro ownership, AeroSpace re-enable, config updates, backup restoration, directory configs, the Neovim opt-in, master-stack retirement, workspace layout modes, the calendar popup, the Apple menu, the front-app menus, Neovim theme following, the battery popup, and keep-awake survival, identity, boot scoping, deadlines, and bar reconciliation.'
