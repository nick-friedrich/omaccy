#!/usr/bin/env bash
set -u

# Clear a workspace, so the next thing opened there starts from nothing:
#
#   - Every window on it is closed. An application quits when that was its last
#     window, and one with windows on other workspaces keeps running there.
#     Closing goes through the application, so unsaved work still asks first,
#     and a window kept open that way simply stays.
#   - No application is remembered as living there any more, so reopening one
#     no longer sends it back (window-memory.sh forget).
#   - Its layout mode is dropped and it follows default_layout again
#     (layout.sh reset).
#
# The memory is forgotten only after the windows are gone: closing a window
# moves focus, and the record that runs on every focus change would otherwise
# write back what was just forgotten. A window still open by then is learned
# again on the next record, which is right, since the application still lives
# there.
#
# Usage: clear-workspace.sh [workspace]   (defaults to the focused workspace)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN="${AEROSPACE_BIN:-$(command -v aerospace 2>/dev/null)}"
if [[ -z "$BIN" ]]; then
  for candidate in /opt/homebrew/bin/aerospace /usr/local/bin/aerospace; do
    [[ -x "$candidate" ]] && BIN="$candidate" && break
  done
fi
if [[ -z "$BIN" ]]; then
  echo "AeroSpace is not installed." >&2
  exit 1
fi
export AEROSPACE_BIN="$BIN"

workspace="${1:-}"
[[ -n "$workspace" ]] || workspace="$("$BIN" list-workspaces --focused 2>/dev/null | head -n 1)"
if [[ -z "$workspace" ]]; then
  echo "No workspace to clear." >&2
  exit 1
fi

window_count() {
  local count
  count="$("$BIN" list-windows --workspace "$workspace" --count 2>/dev/null)"
  printf '%s\n' "${count:-0}"
}

for id in $("$BIN" list-windows --workspace "$workspace" --format '%{window-id}' 2>/dev/null); do
  "$BIN" close --quit-if-last-window --window-id "$id" >/dev/null 2>&1
done

# Applications close their windows in their own time. Three seconds covers an
# ordinary quit; a save prompt holds its window for longer, and is left to it.
waited=0
while [[ "$(window_count)" -gt 0 ]] && (( waited < ${OMACCY_CLEAR_WAIT_TICKS:-30} )); do
  sleep 0.1
  waited=$((waited + 1))
done

bash "$HERE/window-memory.sh" forget "$workspace"
bash "$HERE/layout.sh" reset "$workspace"

sketchybar_bin="${OMACCY_SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null)}"
if [[ -z "$sketchybar_bin" ]]; then
  for candidate in /opt/homebrew/bin/sketchybar /usr/local/bin/sketchybar; do
    [[ -x "$candidate" ]] && sketchybar_bin="$candidate" && break
  done
fi
[[ -n "$sketchybar_bin" ]] &&
  "$sketchybar_bin" --trigger aerospace_workspace_change >/dev/null 2>&1

remaining="$(window_count)"
if [[ "$remaining" -gt 0 ]]; then
  echo "Workspace $workspace cleared; $remaining window(s) are still open."
else
  echo "Workspace $workspace cleared."
fi
