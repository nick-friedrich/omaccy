#!/usr/bin/env bash

# Rosé Pine.

BAR_BG=0xff191724      # base
ITEM_BG=0xff1f1d2e     # surface
BORDER=0xff26233a      # overlay
ACCENT=0xffc4a7e7      # iris
TEXT=0xffe0def4        # text
MUTED=0xff6e6a86       # muted
OK=0xff9ccfd8          # foam
DANGER=0xffeb6f92      # love

# Ghostty ships this palette as a built-in theme name.
GHOSTTY_THEME="Rose Pine"

# Whether this is a light or a dark palette. Drives the macOS appearance when
# that switch is on, and nothing otherwise.
APPEARANCE="dark"

# VS Code and Cursor: the marketplace extension shipping this palette, and the
# theme label it contributes. An empty VSCODE_EXTENSION means VS Code has the
# label built in, so nothing needs installing.
VSCODE_EXTENSION="mvllow.rose-pine"
VSCODE_THEME="Rosé Pine"
