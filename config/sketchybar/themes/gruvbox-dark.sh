#!/usr/bin/env bash

# Gruvbox (dark).

BAR_BG=0xff1d2021      # bg0_h
ITEM_BG=0xff282828     # bg0
BORDER=0xff504945      # bg2
ACCENT=0xfffe8019      # orange
TEXT=0xffebdbb2        # fg
MUTED=0xff928374       # gray
OK=0xffb8bb26          # green
DANGER=0xfffb4934      # red

# Ghostty ships this palette as a built-in theme name.
GHOSTTY_THEME="Gruvbox Dark"

# Whether this is a light or a dark palette. Drives the macOS appearance when
# that switch is on, and nothing otherwise.
APPEARANCE="dark"

# VS Code and Cursor: the marketplace extension shipping this palette, and the
# theme label it contributes. An empty VSCODE_EXTENSION means VS Code has the
# label built in, so nothing needs installing.
VSCODE_EXTENSION="jdinhlife.gruvbox"
VSCODE_THEME="Gruvbox Dark Hard"

# Neovim: the colorscheme config/nvim/lua/plugins/omaccy-theme.lua installs
# for this palette. Running nvim instances switch to it as the theme changes.
NVIM_COLORSCHEME="gruvbox"

# herdr: the built-in theme its UI uses for this palette. "terminal" takes
# the terminal's own colors, for palettes herdr has no theme of its own for.
HERDR_THEME="gruvbox"
