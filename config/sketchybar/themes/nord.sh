#!/usr/bin/env bash

# Nord.

BAR_BG=0xff2e3440      # nord0
ITEM_BG=0xff3b4252     # nord1
BORDER=0xff4c566a      # nord3
ACCENT=0xff88c0d0      # nord8
TEXT=0xffeceff4        # nord6
MUTED=0xff7b88a1       # brightened nord3
OK=0xffa3be8c          # green
DANGER=0xffbf616a      # red

# Ghostty ships this palette as a built-in theme name.
GHOSTTY_THEME="Nord"

# Whether this is a light or a dark palette. Drives the macOS appearance when
# that switch is on, and nothing otherwise.
APPEARANCE="dark"

# VS Code and Cursor: the marketplace extension shipping this palette, and the
# theme label it contributes. An empty VSCODE_EXTENSION means VS Code has the
# label built in, so nothing needs installing.
VSCODE_EXTENSION="arcticicestudio.nord-visual-studio-code"
VSCODE_THEME="Nord"

# Neovim: the colorscheme config/nvim/lua/plugins/omaccy-theme.lua installs
# for this palette. Running nvim instances switch to it as the theme changes.
NVIM_COLORSCHEME="nord"

# herdr: the built-in theme its UI uses for this palette. "terminal" takes
# the terminal's own colors, for palettes herdr has no theme of its own for.
HERDR_THEME="nord"
