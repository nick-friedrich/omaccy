#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") {start|stop|toggle}" >&2
  exit 2
}

AEROSPACE_LAST_ERROR=""
AEROSPACE_DISABLED_MARKER="$HOME/.omaccy/aerospace-disabled"

aerospace_is_running() {
  local output
  if output="$(aerospace list-workspaces --all 2>&1)"; then
    AEROSPACE_LAST_ERROR=""
    return 0
  fi
  AEROSPACE_LAST_ERROR="$output"
  return 1
}

ipc_is_restricted() {
  [[ "$AEROSPACE_LAST_ERROR" == *"Operation not permitted"* ]]
}

warn_restricted_ipc() {
  echo "WARNING: This shell cannot connect to AeroSpace's local server." >&2
  echo "AeroSpace is installed and configured, but its state could not be changed here." >&2
  echo "Launch AeroSpace from Applications, or rerun this command from a normal terminal." >&2
}

# Uninstall disables tiling without quitting the app. That server rejects normal
# queries, but still accepts enable on. Re-enable before checking readiness.
aerospace_ready_for_start() {
  if aerospace_is_running; then
    return 0
  fi
  if [[ "$AEROSPACE_LAST_ERROR" == *"server is disabled"* ]]; then
    local enable_error
    if ! enable_error="$(aerospace enable on 2>&1)"; then
      AEROSPACE_LAST_ERROR="$enable_error"
      return 1
    fi
    aerospace_is_running
    return $?
  fi
  return 1
}

start_aerospace() {
  if ! aerospace_ready_for_start; then
    local launch_error
    if ! launch_error="$(/usr/bin/open /Applications/AeroSpace.app 2>&1)"; then
      if [[ -d /Applications/AeroSpace.app ]]; then
        echo "WARNING: This shell could not launch AeroSpace: $launch_error" >&2
        echo "AeroSpace is installed and configured; launch it once from Applications." >&2
        return 0
      fi
      echo "ERROR: AeroSpace.app is not installed." >&2
      exit 1
    fi

    # The CLI is installed before the app finishes opening. Wait for its IPC
    # socket rather than guessing how long application startup will take.
    local attempt
    for attempt in {1..50}; do
      aerospace_ready_for_start && break
      sleep 0.1
    done
  fi

  if ! aerospace_ready_for_start; then
    if ipc_is_restricted; then
      warn_restricted_ipc
      return 0
    fi
    echo "ERROR: AeroSpace did not become ready." >&2
    [[ -n "$AEROSPACE_LAST_ERROR" ]] && echo "$AEROSPACE_LAST_ERROR" >&2
    exit 1
  fi

  # This also validates and applies a newly installed config when AeroSpace
  # was already running before Omaccy was installed or updated.
  aerospace reload-config --no-gui
  aerospace enable on
  rm -f "$AEROSPACE_DISABLED_MARKER"
}

stop_aerospace() {
  mkdir -p "$(dirname "$AEROSPACE_DISABLED_MARKER")"
  touch "$AEROSPACE_DISABLED_MARKER"
  # A stopped app is already equivalent to disabled tiling.
  if ! aerospace_is_running; then
    ipc_is_restricted && warn_restricted_ipc
    return 0
  fi
  aerospace enable off
}

case "${1:-}" in
  start) start_aerospace ;;
  stop) stop_aerospace ;;
  toggle)
    if ! aerospace_is_running; then
      start_aerospace
    else
      if aerospace enable toggle; then
        mkdir -p "$(dirname "$AEROSPACE_DISABLED_MARKER")"
        if [[ -f "$AEROSPACE_DISABLED_MARKER" ]]; then
          rm -f "$AEROSPACE_DISABLED_MARKER"
        else
          touch "$AEROSPACE_DISABLED_MARKER"
        fi
      fi
    fi
    ;;
  *) usage ;;
esac
