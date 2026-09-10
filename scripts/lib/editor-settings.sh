#!/usr/bin/env bash

# The one piece of Omaccy's editor theming that exists twice: these rewrites
# are also implemented in Swift, in OmaccyAppearance, because the launcher
# ships as a signed bundle and cannot reach the checkout these scripts live
# in. Keeping them in their own library is what lets the Swift test suite run
# both over the same fixtures and insist they agree, byte for byte -- the two
# silently disagreed once already, over a carriage return, and corrupted a
# real settings.json.

# Matching a setting by name without building a regex out of it: the keys here
# contain dots, and quoting those safely through `awk -v` is more fragile than
# comparing the quoted key literally.
OMACCY_AWK_ASSIGNMENT='
function is_assignment(line, key,   quoted, rest) {
  sub(/^[[:space:]]*/, "", line)
  quoted = "\"" key "\""
  if (substr(line, 1, length(quoted)) != quoted) return 0
  rest = substr(line, length(quoted) + 1)
  sub(/^[[:space:]]*/, "", rest)
  return substr(rest, 1, 1) == ":"
}
# Where the JSON on a line stops and a comment trailing it begins. A "//"
# inside a string (a URL value) is not a comment, so this tracks quoting
# rather than searching for the characters.
function code_length(line,   i, c, n, in_string, escaped) {
  n = length(line); in_string = 0; escaped = 0
  for (i = 1; i <= n; i++) {
    c = substr(line, i, 1)
    if (in_string) {
      if (escaped) escaped = 0
      else if (c == "\\") escaped = 1
      else if (c == "\"") in_string = 0
    } else if (c == "\"") in_string = 1
    else if (c == "/" && (substr(line, i + 1, 1) == "/" || substr(line, i + 1, 1) == "*")) return i - 1
  }
  return n
}
'

# True when the file sets `window.autoDetectColorScheme` to true. That setting
# makes both editors ignore workbench.colorTheme entirely and swap between the
# preferred light and dark themes with the OS appearance instead, so writing
# the theme without noticing it looks exactly like nothing happening.
editor_follows_os_appearance() {
  local settings="$1"
  [[ -f "$settings" ]] || return 1
  local value
  value="$(awk -v key="window.autoDetectColorScheme" "$OMACCY_AWK_ASSIGNMENT"'
    is_assignment($0, key) {
      line = ($0 ~ /\r$/) ? substr($0, 1, length($0) - 1) : $0
      code = substr(line, 1, code_length(line))
      sub(/^[^:]*:[[:space:]]*/, "", code)
      sub(/[[:space:]]*,?[[:space:]]*$/, "", code)
      print code
      exit
    }
  ' "$settings")"
  [[ "$value" == "true" ]]
}

# Rewrites just the named setting's line, leaving every other line -- comments
# and trailing commas included -- exactly as it was. These files are JSONC, so
# a parse-and-reserialize round-trip would silently delete the user's
# comments; this stays line-based for the same reason theme.sh's Ghostty
# rewrite does.
# `quoted` defaults to 1; pass 0 for a value that is JSON in its own right,
# such as the boolean below.
write_editor_setting() {
  local settings="$1" key="$2" value="$3" quoted="${4:-1}" tmp
  tmp="$(mktemp)"
  local present
  present="$(awk -v key="$key" "$OMACCY_AWK_ASSIGNMENT"'is_assignment($0, key) { print "1"; exit }' "$settings")"
  if [[ -n "$present" ]]; then
    awk -v key="$key" -v value="$value" -v quoted="$quoted" "$OMACCY_AWK_ASSIGNMENT"'
      !replaced && is_assignment($0, key) {
        match($0, /^[[:space:]]*/)
        indent = substr($0, 1, RLENGTH)
        # A CRLF file keeps its carriage return, so the rewritten line does not
        # become the one odd terminator in the file.
        carriage = ($0 ~ /\r$/) ? "\r" : ""
        line = carriage == "" ? $0 : substr($0, 1, length($0) - 1)
        split_at = code_length(line)
        code = substr(line, 1, split_at)
        comment = substr(line, split_at + 1)
        # Read the comma off the JSON alone: `"…": "Nord", // pinned` ends in
        # the comment, and taking the comma from the whole line drops it and
        # breaks the file, the same way a carriage return did.
        comma = (code ~ /,[[:space:]]*$/) ? "," : ""
        quote = quoted == "1" ? "\"" : ""
        print indent "\"" key "\": " quote value quote comma (comment == "" ? "" : " " comment) carriage
        replaced = 1
        next
      }
      { print }
    ' "$settings" > "$tmp"
  else
    # No entry yet, so it goes in first. Only the shape the editors write
    # themselves -- "{" alone on the opening line -- is handled; a hand-packed
    # object is left alone rather than guessed at.
    if [[ "$(head -n 1 "$settings" | tr -d '[:space:]')" != "{" ]]; then
      rm -f "$tmp"
      echo "Could not place $key in $settings; set it to \"$value\" yourself." >&2
      return 1
    fi
    local indent body comma carriage=""
    indent="$(awk 'NR > 1 && /[^[:space:]]/ { match($0, /^[[:space:]]*/); print substr($0, 1, RLENGTH); exit }' "$settings")"
    [[ -n "$indent" ]] || indent="  "
    body="$(sed -n '2,$p' "$settings" | tr -d '[:space:]')"
    comma=","
    [[ -z "$body" || "$body" == "}" ]] && comma=""
    head -n 1 "$settings" | grep -q $'\r' && carriage=$'\r'
    awk -v key="$key" -v value="$value" -v quoted="$quoted" -v indent="$indent" -v comma="$comma" -v carriage="$carriage" '
      NR == 1 { quote = quoted == "1" ? "\"" : ""
                print; print indent "\"" key "\": " quote value quote comma carriage; next }
      { print }
    ' "$settings" > "$tmp"
  fi
  # Copied back rather than moved so the file keeps its inode and permissions.
  # awk terminates every record, including a final line that never had a
  # newline of its own, so a file that did not end in one gets that byte taken
  # back off: the rewrite is supposed to touch one line and nothing else.
  # Swift's line join preserves this for free, which is exactly the kind of
  # difference the parity test exists to catch.
  local size
  size="$(wc -c < "$tmp" | tr -d '[:space:]')"
  if [[ -n "$(tail -c 1 "$settings")" && "$size" -gt 0 ]]; then
    head -c "$((size - 1))" "$tmp" > "$settings"
  else
    cat "$tmp" > "$settings"
  fi
  rm -f "$tmp"
}

# Writes the theme, and switches off the OS-appearance detection that would
# otherwise make the editor ignore it. Omaccy drives the theme once its editor
# switch is on, and leaving the detection in place means the write lands in a
# setting nothing reads -- which is exactly how Cursor came to sit on its own
# theme while its settings.json said otherwise.
write_editor_theme() {
  local settings="$1" label="$2"
  write_editor_setting "$settings" "workbench.colorTheme" "$label" || return 1
  editor_follows_os_appearance "$settings" || return 0
  write_editor_setting "$settings" "window.autoDetectColorScheme" "false" 0
}
