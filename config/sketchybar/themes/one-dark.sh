#!/usr/bin/env bash

# One Dark (Atom).

BAR_BG=0xff21252b      # darker background
ITEM_BG=0xff282c34     # background
BORDER=0xff3e4451      # selection
ACCENT=0xff61afef      # blue
TEXT=0xffabb2bf        # foreground
MUTED=0xff5c6370       # comment
OK=0xff98c379          # green
DANGER=0xffe06c75      # red

# Ghostty ships this palette as a built-in theme name.
GHOSTTY_THEME="Atom One Dark"

# Whether this is a light or a dark palette. Drives the macOS appearance when
# that switch is on, and nothing otherwise.
APPEARANCE="dark"

# VS Code and Cursor: the marketplace extension shipping this palette, and the
# theme label it contributes. An empty VSCODE_EXTENSION means VS Code has the
# label built in, so nothing needs installing.
VSCODE_EXTENSION="zhuangtongfa.material-theme"
VSCODE_THEME="One Dark Pro"
