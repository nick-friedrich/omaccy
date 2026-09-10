#!/usr/bin/env bash
set -u

# Per-workspace layout modes. Each workspace remembers one, in a single-word
# file under ~/.omaccy/workspace-layout, the way ~/.omaccy/theme and
# ~/.omaccy/font already hold their choices. The SketchyBar tiling item reads
# and writes them; AeroSpace's on-window-detected callback re-asserts them.
#
# The flat modes work because AeroSpace inserts a new window as a sibling of
# the focused one: when every window is a direct child of the root, so is the
# next, and the mode holds without a single window being moved. That is what
# separates this from the master/stack placement it replaces, which moved
# every new window and so overwrote whatever had been arranged by hand.
#
# Usage: layout.sh [current | label | status | set <mode> | apply] [workspace]

STATE_DIR="$HOME/.omaccy/workspace-layout"
DEFAULT_MODE="horizontal"
MODES="horizontal vertical grid recursive accordion"

BIN="${AEROSPACE_BIN:-$(command -v aerospace 2>/dev/null)}"
if [[ -z "$BIN" ]]; then
  for candidate in /opt/homebrew/bin/aerospace /usr/local/bin/aerospace; do
    [[ -x "$candidate" ]] && BIN="$candidate" && break
  done
fi
[[ -n "$BIN" ]] || exit 0

# Explicit argument first, then the workspace of the window that triggered the
# callback -- which is not always the focused one, since a window can be
# detected on a workspace you are not looking at -- and only then the focus.
target_workspace() {
  if [[ -n "${1:-}" ]]; then
    printf '%s\n' "$1"
    return
  fi
  if [[ -n "${AEROSPACE_WINDOW_ID:-}" ]]; then
    local found
    found="$("$BIN" list-windows --all --format '%{window-id}%{tab}%{workspace}' 2>/dev/null |
      awk -F '\t' -v id="$AEROSPACE_WINDOW_ID" '$1 == id { print $2; exit }')"
    if [[ -n "$found" ]]; then
      printf '%s\n' "$found"
      return
    fi
  fi
  "$BIN" list-workspaces --focused 2>/dev/null | head -n 1
}

is_mode() {
  case " $MODES " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

current_mode() {
  local workspace="$1" mode=""
  [[ -f "$STATE_DIR/$workspace" ]] &&
    mode="$(head -n 1 "$STATE_DIR/$workspace" | tr -d '[:space:]')"
  is_mode "$mode" || mode="$DEFAULT_MODE"
  printf '%s\n' "$mode"
}

# Named for what the window arrangement looks like rather than for the AeroSpace
# orientation behind it: "Columns" says more from a menu bar than "Horizontal".
mode_label() {
  case "$1" in
    horizontal) printf 'Columns\n' ;;
    vertical) printf 'Rows\n' ;;
    grid) printf 'Grid\n' ;;
    recursive) printf 'Recursive\n' ;;
    accordion) printf 'Accordion\n' ;;
    *) printf 'Tiling\n' ;;
  esac
}

# What list-windows reports for a workspace already in the mode.
expected_root() {
  case "$1" in
    horizontal) printf 'h_tiles\n' ;;
    vertical) printf 'v_tiles\n' ;;
    accordion) printf 'h_accordion\n' ;;
  esac
}

root_layout() {
  "$BIN" list-windows --workspace "$1" --format '%{workspace-root-container-layout}' 2>/dev/null |
    head -n 1
}

window_count() {
  local count
  count="$("$BIN" list-windows --workspace "$1" --count 2>/dev/null)"
  printf '%s\n' "${count:-0}"
}

set_root() {
  local workspace="$1"
  shift
  "$BIN" layout --workspace "$workspace" --root "$@" >/dev/null 2>&1
}

# Windows of the workspace, in the order AeroSpace lists them. Only the grid
# reads this, and only to walk the set; the joins below act on tree neighbours,
# so the order decides which window lands where, not whether a grid is built.
WINDOW_IDS=""
read_window_ids() {
  WINDOW_IDS="$("$BIN" list-windows --workspace "$1" --format '%{window-id}' 2>/dev/null)"
}

window_id_at() {
  printf '%s\n' "$WINDOW_IDS" | sed -n "$(($1 + 1))p"
}

# One column of the grid: join the second window with the first to make the
# container, then push any further ones into it. The container comes out
# vertical on its own, because a nested container is normalized to the
# opposite orientation of its horizontal parent.
build_column() {
  local start="$1" size="$2" index=2
  "$BIN" join-with --window-id "$(window_id_at $((start + 1)))" left >/dev/null 2>&1
  while (( index < size )); do
    "$BIN" move --window-id "$(window_id_at $((start + index)))" \
      --boundaries-action fail left >/dev/null 2>&1
    index=$((index + 1))
  done
}

# As square as the window count allows: three windows make two columns of two
# and one, five make three columns. Fewer than three windows is a row already.
apply_grid() {
  local workspace="$1" count columns base extra index size column
  count="$(window_count "$workspace")"
  if (( count < 3 )); then
    apply_full "$workspace" horizontal
    return
  fi

  "$BIN" flatten-workspace-tree --workspace "$workspace" >/dev/null 2>&1
  set_root "$workspace" tiles horizontal
  read_window_ids "$workspace"

  columns=1
  while (( columns * columns < count )); do
    columns=$((columns + 1))
  done
  base=$((count / columns))
  extra=$((count % columns))

  index=0
  column=0
  while (( column < columns )); do
    size=$base
    (( column < extra )) && size=$((size + 1))
    (( size > 1 )) && build_column "$index" "$size"
    index=$((index + size))
    column=$((column + 1))
  done
  "$BIN" balance-sizes --workspace "$workspace" >/dev/null 2>&1
}

# Picking a mode rearranges the workspace outright: flatten what is there, set
# the orientation, and even the sizes out, because a mode you just chose should
# be visible immediately.
apply_full() {
  local workspace="$1" mode="$2"
  case "$mode" in
    recursive)
      # Enforces nothing on purpose -- this is the mode for leaving the tree
      # alone, so switching to it must not disturb what is already there.
      ;;
    accordion)
      set_root "$workspace" accordion horizontal
      ;;
    grid)
      apply_grid "$workspace"
      ;;
    horizontal|vertical)
      "$BIN" flatten-workspace-tree --workspace "$workspace" >/dev/null 2>&1
      if [[ "$mode" == vertical ]]; then
        set_root "$workspace" tiles vertical
      else
        set_root "$workspace" tiles horizontal
      fi
      "$BIN" balance-sizes --workspace "$workspace" >/dev/null 2>&1
      ;;
  esac
}

# Re-assertion, which is what runs on every new window. The flat modes only
# correct the root orientation when it has drifted, so sizes you have adjusted
# survive; a flat workspace stays flat by itself, which is why this is almost
# always a no-op. Only the grid has to be rebuilt.
apply_current() {
  local workspace="$1" mode expected
  mode="$(current_mode "$workspace")"
  case "$mode" in
    recursive)
      return 0
      ;;
    grid)
      apply_grid "$workspace"
      ;;
    *)
      [[ "$(window_count "$workspace")" -gt 0 ]] || return 0
      expected="$(expected_root "$mode")"
      [[ "$(root_layout "$workspace")" == "$expected" ]] && return 0
      case "$mode" in
        vertical) set_root "$workspace" tiles vertical ;;
        accordion) set_root "$workspace" accordion horizontal ;;
        *) set_root "$workspace" tiles horizontal ;;
      esac
      ;;
  esac
}

set_mode() {
  local workspace="$1" mode="$2"
  if ! is_mode "$mode"; then
    echo "Unknown layout mode: $mode" >&2
    echo "Available modes: $MODES" >&2
    return 2
  fi
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$mode" > "$STATE_DIR/$workspace"
  apply_full "$workspace" "$mode"
}

command="${1:-current}"
case "$command" in
  current)
    workspace="$(target_workspace "${2:-}")"
    [[ -n "$workspace" ]] || exit 0
    current_mode "$workspace"
    ;;
  label)
    workspace="$(target_workspace "${2:-}")"
    [[ -n "$workspace" ]] || exit 0
    mode_label "$(current_mode "$workspace")"
    ;;
  # Both halves in one line, so the bar redraw costs one process rather than
  # two: it needs the label to print and the mode to mark the active row.
  status)
    workspace="$(target_workspace "${2:-}")"
    [[ -n "$workspace" ]] || exit 0
    mode="$(current_mode "$workspace")"
    printf '%s\t%s\n' "$mode" "$(mode_label "$mode")"
    ;;
  set)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: layout.sh set <mode> [workspace]" >&2
      exit 2
    fi
    workspace="$(target_workspace "${3:-}")"
    [[ -n "$workspace" ]] || exit 0
    set_mode "$workspace" "$2"
    ;;
  apply)
    workspace="$(target_workspace "${2:-}")"
    [[ -n "$workspace" ]] || exit 0
    apply_current "$workspace"
    ;;
  *)
    echo "Usage: layout.sh [current | label | status | set <mode> | apply] [workspace]" >&2
    exit 2
    ;;
esac
