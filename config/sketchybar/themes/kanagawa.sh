#!/usr/bin/env bash

# Kanagawa (wave).

BAR_BG=0xff16161d      # sumiInk0
ITEM_BG=0xff1f1f28     # sumiInk3
BORDER=0xff363646      # sumiInk5
ACCENT=0xff7e9cd8      # crystalBlue
TEXT=0xffdcd7ba        # fujiWhite
MUTED=0xff727169       # fujiGray
OK=0xff98bb6c          # springGreen
DANGER=0xffe82424      # samuraiRed

# Ghostty ships this palette as a built-in theme name.
GHOSTTY_THEME="Kanagawa Wave"

# Whether this is a light or a dark palette. Drives the macOS appearance when
# that switch is on, and nothing otherwise.
APPEARANCE="dark"

# VS Code and Cursor: the marketplace extension shipping this palette, and the
# theme label it contributes. An empty VSCODE_EXTENSION means VS Code has the
# label built in, so nothing needs installing.
VSCODE_EXTENSION="metaphore.kanagawa-vscode-color-theme"
VSCODE_THEME="Kanagawa Wave"
