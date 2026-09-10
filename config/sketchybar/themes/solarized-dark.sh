#!/usr/bin/env bash

# Solarized (dark).

BAR_BG=0xff002b36      # base03
ITEM_BG=0xff073642     # base02
BORDER=0xff586e75      # base01
ACCENT=0xff268bd2      # blue
TEXT=0xff93a1a1        # base1
MUTED=0xff657b83       # base00
OK=0xff859900          # green
DANGER=0xffdc322f      # red

# Ghostty ships this palette as a built-in theme name.
GHOSTTY_THEME="iTerm2 Solarized Dark"

# Whether this is a light or a dark palette. Drives the macOS appearance when
# that switch is on, and nothing otherwise.
APPEARANCE="dark"

# VS Code and Cursor: the marketplace extension shipping this palette, and the
# theme label it contributes. An empty VSCODE_EXTENSION means VS Code has the
# label built in, so nothing needs installing.
VSCODE_EXTENSION=""
VSCODE_THEME="Solarized Dark"
