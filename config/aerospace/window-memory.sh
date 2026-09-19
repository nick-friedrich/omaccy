#!/usr/bin/env bash

# Remember which workspace each application lives in, so relaunching it puts it
# back rather than on top of whatever you are doing.
#
# Nothing here is configured by hand. The mapping is learned from where you
# actually keep your windows, and three rules keep it matching what you meant:
#
#   - Only an application's FIRST window is placed. Open a second window while
#     you are somewhere else and it stays there, because you asked for a window
#     here, not for the application to move.
#   - An application already living where it is remembered stays remembered
#     there, even while a second window of it sits on another workspace. Only
#     when nothing of it is left on the remembered workspace does the memory
#     move on.
#   - Applications with no windows right now keep their entry. Memory is merged
#     rather than rewritten, so a restart with half your applications closed
#     does not forget where the rest of them live.
#   - Only regular applications, the kind with a Dock icon, are remembered or
#     placed. Launchers, Touch ID and password prompts, updaters and menu bar
#     apps put up windows too, and remembering them meant a Command+Space or a
#     Touch ID prompt could carry you off to wherever one was last seen.
#   - You follow the window home only when you just launched the application,
#     because one you just started and cannot see is worse than one that opened
#     in the wrong place. A window from an application that was already running
#     -- a link opening Chrome, an application putting up a window behind your
#     back -- goes home quietly and leaves you where you are.
#
# `record` snapshots every window; it runs on workspace and focus changes, the
# second of which is what catches a window being closed. `place` runs from the
# on-window-detected rule in aerospace.toml for one new window. `forget` drops
# every application remembered on one workspace, for clear-workspace.sh.

set -uo pipefail

STATE_FILE="${OMACCY_DIR:-$HOME/.omaccy}/window-placement"

# How long after launching an application its first window still counts as the
# one you started it for. Generous, because a heavy application can take a few
# seconds to put its window up.
FOLLOW_LAUNCH_SECONDS=30

aerospace_bin() {
  if [[ -n "${AEROSPACE_BIN:-}" && -x "${AEROSPACE_BIN}" ]]; then
    echo "$AEROSPACE_BIN"
  elif [[ -x /opt/homebrew/bin/aerospace ]]; then
    echo /opt/homebrew/bin/aerospace
  elif [[ -x /usr/local/bin/aerospace ]]; then
    echo /usr/local/bin/aerospace
  else
    return 1
  fi
}

# One line per running process: "<pid>|<bundle-id>|<type>". The type is
# Foreground for a regular application, UIElement for an agent with no Dock icon
# (launchers, menu bar apps, the Touch ID prompt) and BackgroundOnly otherwise.
running_apps() {
  lsappinfo list 2>/dev/null | awk '
    /bundleID=/ {
      bundle = $0
      sub(/.*bundleID=/, "", bundle)
      gsub(/"/, "", bundle)
      sub(/[ \t]+$/, "", bundle)
      if (bundle ~ /NULL/) bundle = ""
    }
    /^[ \t]*pid = / {
      pid = $0
      sub(/.*pid = /, "", pid)
      sub(/ .*/, "", pid)
      type = ""
      if (match($0, /type="[^"]*"/)) type = substr($0, RSTART + 6, RLENGTH - 7)
      print pid "|" bundle "|" type
      bundle = ""
    }
  '
}

is_regular_app() {
  lsappinfo info -only ApplicationType "$1" 2>/dev/null | grep -q 'type="Foreground"'
}

# Seconds since the process started, from ps's [[dd-]hh:]mm:ss.
process_age() {
  ps -o etime= -p "$1" 2>/dev/null | awk '
    {
      n = split($1, part, /[-:]/)
      if (n < 2) exit 1
      seconds = part[n] + part[n - 1] * 60
      if (n >= 3) seconds += part[n - 2] * 3600
      if (n >= 4) seconds += part[n - 3] * 86400
      print seconds
    }
  '
}

# One line per application: "<bundle-id>|<workspace>".
record() {
  local aerospace listing apps tmp
  aerospace="$(aerospace_bin)" || return 0

  listing="$("$aerospace" list-windows --all --format '%{app-pid}|%{app-bundle-id}|%{workspace}' 2>/dev/null)" || return 0
  # No windows at all says nothing about where anything lives. Leaving the file
  # untouched is what carries the memory through a logout, when this can run
  # before a single window is back.
  [[ -n "$listing" ]] || return 0

  # Without knowing which processes are regular applications, a launcher or a
  # Touch ID prompt would be remembered like one. Better to learn nothing.
  apps="$(running_apps)"
  [[ -n "$apps" ]] || return 0

  mkdir -p "$(dirname "$STATE_FILE")" || return 0
  tmp="$(mktemp "${STATE_FILE}.XXXXXX")" || return 0
  [[ -f "$STATE_FILE" ]] || : > "$STATE_FILE"

  printf '%s\n' "$listing" \
    | awk -F'|' '
        # First the running processes, then the memory as it stands, then the
        # live windows.
        FILENAME == ARGV[1] {
          type[$1] = $3
          if ($2 == "") next
          if ($3 == "Foreground") regular[$2] = 1
          else agent[$2] = 1
          next
        }
        FILENAME == ARGV[2] {
          # An agent remembered before agents were left out is dropped, so a
          # stale entry cannot come back to life.
          if (($1 in agent) && !($1 in regular)) next
          if (NF == 2 && $1 != "" && $2 != "") remembered[$1] = $2
          next
        }
        NF == 3 && type[$1] == "Foreground" && $2 != "" && $3 != "" {
          live[$2] = 1
          count[$2, $3]++
        }
        END {
          # Applications with nothing open keep the workspace they had.
          for (app in remembered)
            if (!(app in live)) print app "|" remembered[app]

          for (app in live) {
            home = remembered[app]
            # Still present where we remember it: leave the memory alone, so a
            # second window elsewhere cannot drag an application off its home.
            if (home != "" && ((app, home) in count)) {
              print app "|" home
              continue
            }
            # Otherwise it has genuinely moved. Take the workspace holding most
            # of its windows, and the lowest-numbered one to break a tie so the
            # answer does not depend on hash order.
            best = ""; best_count = 0
            for (key in count) {
              split(key, part, SUBSEP)
              if (part[1] != app) continue
              if (count[key] > best_count ||
                  (count[key] == best_count && (best == "" || part[2] < best))) {
                best_count = count[key]
                best = part[2]
              }
            }
            if (best != "") print app "|" best
          }
        }
      ' <(printf '%s\n' "$apps") "$STATE_FILE" - \
    > "$tmp" || { rm -f "$tmp"; return 0; }

  # An empty result means the merge went wrong; keep what we already had.
  if [[ -s "$tmp" ]]; then
    mv "$tmp" "$STATE_FILE" 2>/dev/null || rm -f "$tmp"
  else
    rm -f "$tmp"
  fi
}

# Unlike record, an empty result is fine here: clearing the only workspace
# anything was remembered on leaves nothing to remember.
forget() {
  local workspace="$1" tmp
  [[ -n "$workspace" && -f "$STATE_FILE" ]] || return 0
  tmp="$(mktemp "${STATE_FILE}.XXXXXX")" || return 0
  awk -F'|' -v workspace="$workspace" '$2 != workspace' "$STATE_FILE" > "$tmp" ||
    { rm -f "$tmp"; return 0; }
  mv "$tmp" "$STATE_FILE" 2>/dev/null || rm -f "$tmp"
}

# Did this window take focus? That is what separates a window you opened from
# one an application put up on its own: macOS focuses the window you asked for
# as it appears. The callback can beat the focus notification by a few
# milliseconds, so ask again briefly before concluding nobody asked for it.
# The wait costs a background window a moment on screen before it is moved,
# and never delays one you are about to follow.
window_is_focused() {
  local aerospace="$1" window_id="$2" attempt focused

  for attempt in 1 2 3 4; do
    focused="$("$aerospace" list-windows --focused --format '%{window-id}' 2>/dev/null | head -n 1)"
    [[ "$focused" == "$window_id" ]] && return 0
    sleep 0.05
  done
  return 1
}

place() {
  local window_id="$1"
  local aerospace listing app pid windows remembered current age

  [[ -n "$window_id" ]] || return 0
  [[ -f "$STATE_FILE" ]] || return 0
  aerospace="$(aerospace_bin)" || return 0

  listing="$("$aerospace" list-windows --all --format '%{window-id}|%{app-bundle-id}|%{workspace}|%{app-pid}' 2>/dev/null)" || return 0

  app="$(printf '%s\n' "$listing" \
    | awk -F'|' -v id="$window_id" '$1 == id { print $2; exit }')"
  [[ -n "$app" ]] || return 0
  pid="$(printf '%s\n' "$listing" \
    | awk -F'|' -v id="$window_id" '$1 == id { print $4; exit }')"
  # A launcher, a Touch ID prompt or a menu bar app is never sent anywhere: it
  # appears where you are because that is where you need it.
  [[ -n "$pid" ]] && is_regular_app "$pid" || return 0

  # Only the application's first window is sent home. Any further window was
  # asked for while you were somewhere, and belongs where you asked for it.
  windows="$(printf '%s\n' "$listing" | awk -F'|' -v app="$app" '$2 == app' | wc -l | tr -d ' ')"
  [[ "$windows" == "1" ]] || return 0

  remembered="$(awk -F'|' -v app="$app" '$1 == app { print $2; exit }' "$STATE_FILE")"
  # Never seen before: leave it where it opened and let record() learn from it.
  [[ -n "$remembered" ]] || return 0

  current="$(printf '%s\n' "$listing" \
    | awk -F'|' -v id="$window_id" '$1 == id { print $3; exit }')"
  [[ "$current" != "$remembered" ]] || return 0

  # --focus-follows-window switches to the remembered workspace along with the
  # window, in one move: nothing is on screen in between, and AeroSpace fires
  # its workspace-change callback so the bar keeps up. Only an application you
  # just launched takes you along. Focus alone is not enough: an application
  # that was already running takes focus too when a link opens in it.
  age="$(process_age "$pid")"
  if [[ -n "$age" ]] && (( age <= FOLLOW_LAUNCH_SECONDS )) &&
    window_is_focused "$aerospace" "$window_id"; then
    "$aerospace" move-node-to-workspace --window-id "$window_id" \
      --focus-follows-window "$remembered" >/dev/null 2>&1 || return 0
  else
    "$aerospace" move-node-to-workspace --window-id "$window_id" "$remembered" >/dev/null 2>&1 || return 0
  fi
}

case "${1:-}" in
  record) record ;;
  place)  place "${2:-}" ;;
  forget) forget "${2:-}" ;;
  *) echo "Usage: $(basename "$0") record | place <window-id> | forget <workspace>" >&2; exit 1 ;;
esac
