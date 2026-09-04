#!/usr/bin/env bash
set -u

# AeroSpace initially inserts a window beside whichever window is focused.
# Move the new window into the right-hand slave container and then to its
# bottom, preserving the first/root-left window as the master.
aerospace_bin="${AEROSPACE_BIN:-$(command -v aerospace 2>/dev/null)}"
window_id="${AEROSPACE_WINDOW_ID:-}"

[[ -n "$aerospace_bin" && -n "$window_id" ]] || exit 0

window_record() {
  "$aerospace_bin" list-windows --all \
    --format '%{window-id}%{tab}%{workspace}%{tab}%{window-parent-container-layout}' |
    awk -F '\t' -v target="$window_id" '$1 == target { print; exit }'
}

record="$(window_record)"
[[ -n "$record" ]] || exit 0
IFS=$'\t' read -r _ workspace parent_layout <<< "$record"
window_count="$("$aerospace_bin" list-windows --workspace "$workspace" --count)"

# The root naturally handles the first two side-by-side windows.
(( window_count > 2 )) || exit 0

if [[ "$parent_layout" == "h_tiles" ]]; then
  # If the window was opened from the master, this enters an existing slave
  # container. With exactly three windows it instead moves to the root's end.
  "$aerospace_bin" move --window-id "$window_id" \
    --boundaries-action fail right 2>/dev/null || true

  record="$(window_record)"
  [[ -n "$record" ]] || exit 0
  IFS=$'\t' read -r _ _ parent_layout <<< "$record"

  if [[ "$parent_layout" == "h_tiles" ]]; then
    # Create the right-hand vertical stack when the third window arrives.
    "$aerospace_bin" join-with --window-id "$window_id" left 2>/dev/null ||
      "$aerospace_bin" join-with --window-id "$window_id" right 2>/dev/null || true
    exit 0
  fi
fi

if [[ "$parent_layout" == "v_tiles" ]]; then
  # Append to the bottom regardless of which slave/master launched the window.
  while "$aerospace_bin" move --window-id "$window_id" \
      --boundaries-action fail down 2>/dev/null; do
    :
  done
fi
