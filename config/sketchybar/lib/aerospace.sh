#!/usr/bin/env bash

# Locates the aerospace CLI wherever Homebrew installed it. Shared by
# sketchybarrc and every plugin that needs to query or drive AeroSpace.
find_aerospace() {
  command -v aerospace 2>/dev/null || {
    [[ -x /opt/homebrew/bin/aerospace ]] && printf '%s\n' /opt/homebrew/bin/aerospace && return
    [[ -x /usr/local/bin/aerospace ]] && printf '%s\n' /usr/local/bin/aerospace
  }
}
