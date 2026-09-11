#!/usr/bin/env bash

# herdr's theme, set in herdr's own config.toml. Like editor-settings.sh, this
# rewrite exists twice -- here for scripts/theme.sh, and in Swift as
# OmaccyAppearance.herdrConfig for the launcher -- and lives in a library of
# its own so the Swift tests can run both over the same configs and insist
# they agree byte for byte.

# Prints the config at $1 with `name` under [theme] set to $2 and every other
# line as it was: the name line replaced where the table has one, added under
# the header where it has none, and a [theme] table appended where the file
# has none. Always ends in a newline. Line-based rather than parsed, because
# reserializing TOML would drop the user's comments.
#
# $3 and $4 are the accent and panel_bg colors for [theme.custom], or empty
# for none. Omaccy marks each color line it writes with `# omaccy`, so those
# lines -- and only those -- are replaced or removed on the next switch. An
# unmarked accent or panel_bg is the user's own and wins: Omaccy adds none of
# its own beside it.
herdr_config_with_theme() {
  local config="$1" theme="$2" accent="${3:-}" panel_bg="${4:-}"
  awk -v theme="$theme" -v accent="$accent" -v panel_bg="$panel_bg" '
    function table_of(line) {
      sub(/\r$/, "", line)
      if (line ~ /^[ \t]*\[[ \t]*theme[ \t]*\][ \t]*(#.*)?$/) return "theme"
      if (line ~ /^[ \t]*\[[ \t]*theme\.custom[ \t]*\][ \t]*(#.*)?$/) return "theme.custom"
      return "other"
    }
    function custom_key(line) {
      if (line ~ /^[ \t]*accent[ \t]*=/) return "accent"
      if (line ~ /^[ \t]*panel_bg[ \t]*=/) return "panel_bg"
      return ""
    }
    function marked(line) {
      sub(/\r$/, "", line)
      return line ~ /# omaccy$/
    }
    function rewritten(line, entry,   cr) {
      match(line, /^[ \t]*/)
      cr = (substr(line, length(line), 1) == "\r") ? "\r" : ""
      return substr(line, 1, RLENGTH) entry cr
    }
    function custom_entry(key) { return key " = \"" wanted[key] "\" # omaccy" }
    function needed(key) { return wanted[key] != "" && !owned[key] && !written[key] }
    { lines[NR] = $0 }
    END {
      name_entry = "name = \"" theme "\""
      # A value with a quote in it could only come from a misread theme file,
      # and would write broken TOML, so it counts as no color at all.
      wanted["accent"] = index(accent, "\"") ? "" : accent
      wanted["panel_bg"] = index(panel_bg, "\"") ? "" : panel_bg
      keys[1] = "accent"
      keys[2] = "panel_bg"

      # Which table each line is in, and which colors the user set themselves.
      table = ""
      for (i = 1; i <= NR; i++) {
        if (lines[i] ~ /^[ \t]*\[/) {
          table = table_of(lines[i])
          tables[i] = "header"
          if (table == "theme" && !theme_header) theme_header = i
          if (table == "theme.custom" && !custom_header) custom_header = i
          continue
        }
        tables[i] = table
        key = custom_key(lines[i])
        if (table == "theme.custom" && key != "" && !marked(lines[i])) owned[key] = 1
      }

      for (i = 1; i <= NR; i++) {
        if (tables[i] == "theme" && !replaced && lines[i] ~ /^[ \t]*name[ \t]*=/) {
          lines[i] = rewritten(lines[i], name_entry)
          replaced = 1
        } else if (tables[i] == "theme.custom" && (key = custom_key(lines[i])) != "" && marked(lines[i])) {
          if (needed(key)) {
            lines[i] = rewritten(lines[i], custom_entry(key))
            written[key] = 1
          } else {
            dropped[i] = 1
          }
        }
      }

      for (i = 1; i <= NR; i++) {
        if (dropped[i]) continue
        print lines[i]
        if (i == theme_header && !replaced) print name_entry
        if (i == custom_header) for (k = 1; k <= 2; k++) if (needed(keys[k])) print custom_entry(keys[k])
      }
      if (!theme_header) {
        if (NR > 0) print ""
        print "[theme]"
        print name_entry
      }
      if (!custom_header && (needed("accent") || needed("panel_bg"))) {
        print ""
        print "[theme.custom]"
        for (k = 1; k <= 2; k++) if (needed(keys[k])) print custom_entry(keys[k])
      }
    }
  ' "$config"
}
