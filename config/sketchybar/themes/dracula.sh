#!/usr/bin/env bash

# Dracula.

BAR_BG=0xff21222c      # dark background
ITEM_BG=0xff282a36     # background
BORDER=0xff44475a      # current line
ACCENT=0xffbd93f9      # purple
TEXT=0xfff8f8f2        # foreground
MUTED=0xff6272a4       # comment
OK=0xff50fa7b          # green
DANGER=0xffff5555      # red

# Ghostty ships this palette as a built-in theme name.
GHOSTTY_THEME="Dracula"

# Whether this is a light or a dark palette. Drives the macOS appearance when
# that switch is on, and nothing otherwise.
APPEARANCE="dark"

# VS Code and Cursor: the marketplace extension shipping this palette, and the
# theme label it contributes. An empty VSCODE_EXTENSION means VS Code has the
# label built in, so nothing needs installing.
VSCODE_EXTENSION="dracula-theme.theme-dracula"
VSCODE_THEME="Dracula Theme"

# Neovim: the colorscheme config/nvim/lua/plugins/omaccy-theme.lua installs
# for this palette. Running nvim instances switch to it as the theme changes.
NVIM_COLORSCHEME="dracula"

# herdr: the built-in theme its UI uses for this palette. "terminal" takes
# the terminal's own colors, for palettes herdr has no theme of its own for.
HERDR_THEME="dracula"
