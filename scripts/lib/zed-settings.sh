#!/usr/bin/env bash

# Zed's theme, set in Zed's own ~/.config/zed/settings.json. Like
# editor-settings.sh and herdr-settings.sh, this rewrite exists twice -- here
# for scripts/theme.sh, and in Swift as OmaccyAppearance.zedSettings for the
# launcher -- and lives in a library of its own so the Swift tests can run
# both over the same fixtures and insist they agree byte for byte.
#
# Zed differs from VS Code in the two ways that shape everything below.
#
# First, `theme` takes either a name or an object -- {"mode": "system",
# "light": ..., "dark": ...} -- which is Zed's equivalent of VS Code's
# window.autoDetectColorScheme. Omaccy drives the theme once its editor switch
# is on, so the object is replaced outright by the plain name; the untouched
# original is kept in ~/.omaccy/backups first. That means the value being
# rewritten can span several lines, which the single-line rewrite in
# editor-settings.sh has no way to do.
#
# Second, Zed has no `--install-extension` CLI. Its documented route is
# `auto_install_extensions`, an object of extension ids Zed installs at its
# next launch, so following a theme means merging one key into an object
# rather than running a command. Entries already there are left alone --
# including an id set to false, which is someone saying they do not want it.

# Positions below are (line, column) pairs into the file's own lines, and
# every line the rewrite does not touch is printed back exactly as it came in,
# carriage returns and comments included. Parsing and reserializing would drop
# the comments Zed itself writes into a fresh settings.json.
OMACCY_ZED_AWK='
# Walks the file once and records, for each key of the top-level object, where
# its value starts and ends: the first and last non-whitespace characters
# outside comments. Ending at the value itself rather than at the comma that
# follows keeps a trailing comment on the same line out of the span.
function scan(   i, j, n, line, c, ahead, terminates) {
  depth = 0; in_string = 0; escaped = 0; in_block = 0
  awaiting = ""; top_line = 0; nkeys = 0
  for (i = 1; i <= NR; i++) {
    line = lines[i]
    n = length(line)
    for (j = 1; j <= n; j++) {
      c = substr(line, j, 1)
      if (in_block) {
        if (c == "*" && substr(line, j + 1, 1) == "/") { in_block = 0; j++ }
        continue
      }
      if (!in_string && c == "/") {
        ahead = substr(line, j + 1, 1)
        if (ahead == "/") break
        if (ahead == "*") { in_block = 1; j++; continue }
      }
      terminates = (!in_string && depth == 1 && awaiting == "value" \
                    && (c == "," || c == "}" || c == "]"))
      if (awaiting == "value" && !terminates && c != " " && c != "\t" && c != "\r") {
        if (!vfl) { vfl = i; vfc = j }
        vel = i; vec = j
      }
      if (in_string) {
        if (escaped) escaped = 0
        else if (c == "\\") escaped = 1
        else if (c == "\"") {
          in_string = 0
          if (depth == 1 && awaiting == "key") pending = current
        } else current = current c
        continue
      }
      if (c == "\"") { in_string = 1; current = ""; continue }
      if (c == "{" || c == "[") {
        depth++
        if (depth == 1 && c == "{" && !top_line) {
          top_line = i; top_col = j; awaiting = "key"
        }
        continue
      }
      if (c == "}" || c == "]") {
        if (terminates) close_value(i)
        depth--
        continue
      }
      if (depth == 1 && c == ":" && awaiting == "key") {
        awaiting = "value"; name = pending; vfl = 0; vel = 0
        continue
      }
      if (terminates && c == ",") close_value(i)
    }
  }
}

function close_value(i) {
  awaiting = "key"
  if (!vfl) return
  nkeys++
  keys[nkeys] = name
  starts_line[nkeys] = vfl; starts_col[nkeys] = vfc
  ends_line[nkeys] = vel;   ends_col[nkeys] = vec
}

function index_of(key,   k) {
  for (k = 1; k <= nkeys; k++) if (keys[k] == key) return k
  return 0
}

function carriage(line) { return (line ~ /\r$/) ? "\r" : "" }
function body(line) { return (line ~ /\r$/) ? substr(line, 1, length(line) - 1) : line }

# The text of a value, newlines and all, for looking inside an object without
# a second parser.
function value_text(k,   i, text, from, to) {
  text = ""
  for (i = starts_line[k]; i <= ends_line[k]; i++) {
    from = (i == starts_line[k]) ? starts_col[k] : 1
    to = (i == ends_line[k]) ? ends_col[k] : length(lines[i])
    text = text substr(lines[i], from, to - from + 1)
    if (i < ends_line[k]) text = text "\n"
  }
  return text
}

# The file own indent unit, read off its first indented line, so an inserted
# line sits the way the rest of the file does.
function indent_unit(   i, ws) {
  for (i = 1; i <= NR; i++) {
    if (lines[i] !~ /[^ \t\r]/) continue
    match(lines[i], /^[ \t]+/)
    if (RSTART == 1 && RLENGTH > 0) return substr(lines[i], 1, RLENGTH)
  }
  return "  "
}

function leading(line) {
  match(line, /^[ \t]*/)
  return substr(line, 1, RLENGTH)
}
'

# Prints the settings file at $1 with `theme` set to $2 and $3 merged into
# `auto_install_extensions`, or fails without printing when it cannot place
# the theme. An empty $3 skips the extension entirely, which is how a palette
# Zed has built in says it needs no install.
#
# Always ends in a newline; write_zed_settings below puts back a missing final
# byte, the way editor-settings.sh does.
zed_settings_with_theme() {
  local settings="$1" theme="$2" extension="${3:-}"
  # A quote or backslash could only come from a misread theme file and would
  # write broken JSON; an extension id is a registry slug or nothing.
  case "$theme" in *'"'*|*'\'*|'') return 1 ;; esac
  case "$extension" in *[!A-Za-z0-9._-]*) extension="" ;; esac
  awk -v theme="$theme" -v extension="$extension" "$OMACCY_ZED_AWK"'
    { lines[NR] = $0 }
    END {
      scan()
      if (!top_line) exit 1

      unit = indent_unit()
      theme_key = index_of("theme")
      if (theme_key) {
        # The value may run over several lines -- an object always does -- so
        # the span collapses onto the line it started on, and the lines it
        # covered below that one go away.
        first = starts_line[theme_key]; last = ends_line[theme_key]
        cr = carriage(lines[last])
        head = substr(lines[first], 1, starts_col[theme_key] - 1)
        tail = substr(body(lines[last]), ends_col[theme_key] + 1)
        lines[first] = head "\"" theme "\"" tail cr
        for (i = first + 1; i <= last; i++) dropped[i] = 1
      } else {
        # No entry yet, so it goes in right below the opening brace. Only a
        # brace that ends its line is handled; a hand-packed object is left
        # alone rather than guessed at.
        if (body(lines[top_line]) !~ /\{[ \t]*$/) exit 1
        add_top_entry("\"theme\": \"" theme "\"")
      }

      if (extension != "") merge_extension()
      flush_top_entries()

      for (i = 1; i <= NR; i++) {
        if (!dropped[i]) print lines[i]
        if (after[i] != "") printf "%s", after[i]
      }
    }

    # Entries bound for the top-level object are collected rather than written
    # as they are decided, because the comma each one needs depends on how
    # many follow it -- and into an object that started out empty, the first
    # of two inserts needs one where the last does not.
    function add_top_entry(entry) { pending_top[++npending] = entry }

    function flush_top_entries(   i, cr) {
      cr = carriage(lines[top_line])
      for (i = 1; i <= npending; i++) {
        after[top_line] = after[top_line] unit pending_top[i] \
                          ((i < npending || nkeys > 0) ? "," : "") cr "\n"
      }
    }

    function merge_extension(   k, text, open_line, open_col, line, cr, head, tail, gap, empty) {
      k = index_of("auto_install_extensions")
      if (!k) {
        if (body(lines[top_line]) !~ /\{[ \t]*$/) return
        add_top_entry("\"auto_install_extensions\": { \"" extension "\": true }")
        return
      }
      text = value_text(k)
      # Anything but an object is someone else shape, and merging into it
      # would be a guess.
      if (substr(text, 1, 1) != "{") return
      # Already listed -- as true, or as false by someone who does not want it
      # -- so it stays exactly as it is.
      if (text ~ ("\"" extension "\"[ \t\r\n]*:")) return
      # An object with no entries of its own takes no separating comma.
      empty = (substr(text, 2, length(text) - 2) !~ /[^ \t\r\n]/)

      open_line = starts_line[k]; open_col = starts_col[k]
      line = lines[open_line]
      cr = carriage(line)
      head = substr(body(line), 1, open_col)
      tail = substr(body(line), open_col + 1)
      if (tail ~ /[^ \t]/ || open_line == ends_line[k]) {
        # Something follows the brace on its line, so the entry goes inline
        # and the file keeps every line break it had. The spacing the brace
        # already had is reused, so `{ "html": true }` does not come back as
        # `{"tokyo-night": true,  "html": true }`.
        match(tail, /^[ \t]*/)
        gap = substr(tail, 1, RLENGTH)
        tail = substr(tail, RLENGTH + 1)
        lines[open_line] = head gap "\"" extension "\": true" (empty ? "" : ", ") tail cr
      } else {
        # The brace ends its line, so the entry gets a line of its own, one
        # level in from the line the object opened on.
        lines[open_line] = head tail cr
        after[open_line] = leading(body(line)) unit "\"" extension "\": true" \
                           (empty ? "" : ",") cr "\n" after[open_line]
      }
    }
  ' "$settings"
}

# Writes the theme into Zed settings in place, keeping the file inode, its
# permissions, and a missing final newline. Fails without touching the file
# when the rewrite refuses its shape.
write_zed_settings() {
  local settings="$1" theme="$2" extension="${3:-}" updated tmp
  [[ -f "$settings" ]] || return 1
  # The trailing x keeps command substitution from eating final newlines.
  updated="$(zed_settings_with_theme "$settings" "$theme" "$extension"; printf x)" || return 1
  updated="${updated%x}"
  tmp="$(mktemp)"
  printf '%s' "$updated" > "$tmp"
  local size
  size="$(wc -c < "$tmp" | tr -d '[:space:]')"
  if [[ -n "$(tail -c 1 "$settings")" && "$size" -gt 0 ]]; then
    head -c "$((size - 1))" "$tmp" > "$settings"
  else
    cat "$tmp" > "$settings"
  fi
  rm -f "$tmp"
}
