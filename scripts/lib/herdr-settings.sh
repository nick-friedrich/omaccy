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
herdr_config_with_theme() {
  local config="$1" theme="$2"
  awk -v theme="$theme" '
    { lines[NR] = $0 }
    END {
      entry = "name = \"" theme "\""
      for (i = 1; i <= NR; i++) {
        line = lines[i]
        if (line ~ /^[ \t]*\[/) {
          header = line
          sub(/\r$/, "", header)
          in_theme = (header ~ /^[ \t]*\[[ \t]*theme[ \t]*\][ \t]*(#.*)?$/)
          if (in_theme && !theme_header) theme_header = i
        } else if (in_theme && !replaced && line ~ /^[ \t]*name[ \t]*=/) {
          match(line, /^[ \t]*/)
          cr = (substr(line, length(line), 1) == "\r") ? "\r" : ""
          lines[i] = substr(line, 1, RLENGTH) entry cr
          replaced = 1
        }
      }
      for (i = 1; i <= NR; i++) {
        print lines[i]
        if (i == theme_header && !replaced) print entry
      }
      if (!theme_header) {
        if (NR > 0) print ""
        print "[theme]"
        print entry
      }
    }
  ' "$config"
}
