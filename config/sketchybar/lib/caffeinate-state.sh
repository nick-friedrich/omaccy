#!/usr/bin/env bash

# Owns the keep-awake state under ~/.omaccy, so the SketchyBar plugin and
# uninstall agree on what "on" means and how to take it back down. Sourcing
# this file only defines functions; nothing starts, stops, or writes.
#
# The intent -- the deadline the user asked for -- is the state, and the PID is
# only a cache of the process currently serving it. caffeinate dies more often
# than the intent changes: it inherits the process group of whatever launched
# it, and `brew services restart sketchybar` (a theme or font switch, see
# scripts/theme.sh) makes launchd take down that whole group. Treating the PID
# as the state meant a theme switch silently ended keep-awake. Launching in a
# separate process group avoids the kill, and reconciling against the deadline
# recovers the cases that still get through, including SketchyBar being
# restarted by hand.

OMACCY_STATE_DIR="${OMACCY_STATE_DIR:-$HOME/.omaccy}"
OMACCY_CAFFEINATE_BIN="${OMACCY_CAFFEINATE_BIN:-/usr/bin/caffeinate}"
CAFFEINATE_PID_FILE="$OMACCY_STATE_DIR/caffeinate.pid"
CAFFEINATE_END_FILE="$OMACCY_STATE_DIR/caffeinate.ends-at"
CAFFEINATE_BOOT_FILE="$OMACCY_STATE_DIR/caffeinate.boot"

# Seconds since the epoch at which the running system booted. Used to scope
# resume to the current boot: reviving keep-awake through a SketchyBar restart
# is the point, but silently reviving an indefinite session days and a reboot
# later is not what anyone asked for. A kernel that will not answer yields 0,
# which compares equal to a previously recorded 0 and so resumes rather than
# discarding state we cannot judge.
caffeinate_boot_id() {
  local boottime

  boottime="$(sysctl -n kern.boottime 2>/dev/null || true)"
  # The anchor matters: `.*sec = ` would match through `usec = ` and read back
  # the microseconds instead.
  boottime="$(printf '%s' "$boottime" | sed -n 's/^{ sec = \([0-9][0-9]*\).*/\1/p')"
  printf '%s\n' "${boottime:-0}"
}

caffeinate_read_file() {
  local file="$1"
  local value=""

  [[ -f "$file" ]] || return 1
  value="$(cat "$file" 2>/dev/null || true)"
  value="$(printf '%s' "$value" | tr -d '[:space:]')"
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$value"
}

# True when the recorded PID is a live caffeinate rather than merely a live
# process. PIDs are reused, most visibly across a reboot, and a bare `kill -0`
# would report an unrelated process as keep-awake -- the bar claiming "On"
# while the display sleeps. Matching the command line rather than `ps -o comm=`
# is deliberate: comm reports the interpreter for a script, which the tests
# substitute for the real binary.
caffeinate_process_alive() {
  local pid="$1"
  local command=""

  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  command="$(ps -o command= -p "$pid" 2>/dev/null || true)"
  [[ -n "$command" ]] || return 1
  [[ "$command" == *"$OMACCY_CAFFEINATE_BIN"* ]]
}

caffeinate_is_active() {
  local pid

  pid="$(caffeinate_read_file "$CAFFEINATE_PID_FILE")" || return 1
  caffeinate_process_alive "$pid"
}

caffeinate_clear_state() {
  rm -f "$CAFFEINATE_PID_FILE" "$CAFFEINATE_END_FILE" "$CAFFEINATE_BOOT_FILE"
}

caffeinate_stop() {
  local pid

  if pid="$(caffeinate_read_file "$CAFFEINATE_PID_FILE")" && caffeinate_process_alive "$pid"; then
    kill "$pid" 2>/dev/null || true
  fi
  caffeinate_clear_state
}

# Starts the process and records its PID, leaving the deadline alone so a
# resume keeps serving the original one. `set -m` is what puts caffeinate in a
# process group of its own; without it the child inherits SketchyBar's, and
# launchd ends it along with the service. Job control is restored afterwards
# because this is a library and the caller's shell is not ours to change.
caffeinate_launch() {
  local seconds="${1:-0}"
  local monitor=0
  local pid

  [[ "$seconds" =~ ^[0-9]+$ ]] || return 1
  mkdir -p "$OMACCY_STATE_DIR"

  case "$-" in
    *m*) monitor=1 ;;
  esac
  set -m
  if (( seconds > 0 )); then
    "$OMACCY_CAFFEINATE_BIN" -i -d -t "$seconds" >/dev/null 2>&1 &
  else
    "$OMACCY_CAFFEINATE_BIN" -i -d >/dev/null 2>&1 &
  fi
  pid=$!
  # Monitor mode also makes the shell announce the job when it later dies.
  # Dropping it from the jobs table keeps that chatter out of the plugin's
  # output without giving up the separate process group. It does not detach the
  # process or change its group.
  disown "$pid" 2>/dev/null || true
  (( monitor == 1 )) || set +m

  printf '%s\n' "$pid" > "$CAFFEINATE_PID_FILE"
}

caffeinate_write_intent() {
  local ends_at="$1"

  mkdir -p "$OMACCY_STATE_DIR"
  printf '%s\n' "$ends_at" > "$CAFFEINATE_END_FILE"
  caffeinate_boot_id > "$CAFFEINATE_BOOT_FILE"
}

# duration 0 means indefinite, and is stored as the deadline 0.
caffeinate_start() {
  local duration="${1:-0}"
  local now

  [[ "$duration" =~ ^[0-9]+$ ]] || return 1
  caffeinate_stop
  caffeinate_launch "$duration" || return 1
  if (( duration > 0 )); then
    now="$(date +%s)"
    caffeinate_write_intent "$((now + duration))"
  else
    caffeinate_write_intent 0
  fi
}

# Seconds left to serve, printed for a live deadline. Fails when there is no
# intent, when it belongs to an earlier boot, or when it has run out -- and
# in the cases that will never come back it stops the session outright, so a
# caller that only ever reconciles still tidies up after itself.
caffeinate_remaining() {
  local ends_at
  local recorded_boot
  local now
  local remaining

  ends_at="$(caffeinate_read_file "$CAFFEINATE_END_FILE")" || return 1

  # State with no boot stamp predates this file, or was truncated; either way
  # it describes a process that cannot still be ours.
  recorded_boot="$(caffeinate_read_file "$CAFFEINATE_BOOT_FILE")" || recorded_boot=""
  if [[ "$recorded_boot" != "$(caffeinate_boot_id)" ]]; then
    caffeinate_stop
    return 1
  fi

  if (( ends_at == 0 )); then
    printf '0\n'
    return 0
  fi

  now="$(date +%s)"
  remaining=$((ends_at - now))
  if (( remaining <= 0 )); then
    # Stop rather than merely forget. A `-t` caffeinate normally exits on its
    # own deadline, but a shortened one would otherwise be orphaned: still
    # holding the display awake, with no recorded pid left to stop it by.
    caffeinate_stop
    return 1
  fi
  printf '%s\n' "$remaining"
}

# The reconciliation the plugin runs on every tick: keep-awake is on whenever
# an intent for this boot has not expired, and the process is relaunched for
# the remaining time if something took it down. Returns 0 when awake.
caffeinate_ensure_running() {
  local remaining

  remaining="$(caffeinate_remaining)" || return 1
  caffeinate_is_active && return 0
  caffeinate_launch "$remaining" || return 1
}

# Label for the bar: "On" while indefinite, otherwise the time left rounded up
# so a session never displays as finished while it is still running.
caffeinate_label() {
  local remaining="$1"
  local minutes
  local hours

  if (( remaining == 0 )); then
    printf 'On'
    return
  fi

  minutes=$(((remaining + 59) / 60))
  if (( minutes < 60 )); then
    printf '%dm' "$minutes"
  else
    hours=$((minutes / 60))
    minutes=$((minutes % 60))
    if (( minutes == 0 )); then
      printf '%dh' "$hours"
    else
      printf '%dh %dm' "$hours" "$minutes"
    fi
  fi
}
