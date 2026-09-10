#!/usr/bin/env bash

# Everforest (dark, hard).

BAR_BG=0xff1e2326      # bg_dim
ITEM_BG=0xff272e33     # bg0
BORDER=0xff414b50      # bg3
ACCENT=0xff83c092      # aqua
TEXT=0xffd3c6aa        # fg
MUTED=0xff859289       # grey2
OK=0xffa7c080          # green
DANGER=0xffe67e80      # red

# Ghostty ships this palette as a built-in theme name.
GHOSTTY_THEME="Everforest Dark Hard"

# Whether this is a light or a dark palette. Drives the macOS appearance when
# that switch is on, and nothing otherwise.
APPEARANCE="dark"

# VS Code and Cursor: the marketplace extension shipping this palette, and the
# theme label it contributes. An empty VSCODE_EXTENSION means VS Code has the
# label built in, so nothing needs installing.
VSCODE_EXTENSION="sainnhe.everforest"
VSCODE_THEME="Everforest Dark"
