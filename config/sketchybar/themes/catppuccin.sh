#!/usr/bin/env bash

# Catppuccin Mocha, Omaccy's default palette.

BAR_BG=0xff11111b      # crust
ITEM_BG=0xff1e1e2e     # base
BORDER=0xff45475a      # surface1
ACCENT=0xff89b4fa      # blue
TEXT=0xffcdd6f4        # text
MUTED=0xff7f849c       # overlay1
OK=0xffa6e3a1          # green
DANGER=0xfff38ba8      # red

# Ghostty ships this palette as a built-in theme name.
GHOSTTY_THEME="Catppuccin Mocha"

# Whether this is a light or a dark palette. Drives the macOS appearance when
# that switch is on, and nothing otherwise.
APPEARANCE="dark"

# VS Code and Cursor: the marketplace extension shipping this palette, and the
# theme label it contributes. An empty VSCODE_EXTENSION means VS Code has the
# label built in, so nothing needs installing.
VSCODE_EXTENSION="Catppuccin.catppuccin-vsc"
VSCODE_THEME="Catppuccin Mocha"

# Neovim: the colorscheme config/nvim/lua/plugins/omaccy-theme.lua installs
# for this palette. Running nvim instances switch to it as the theme changes.
NVIM_COLORSCHEME="catppuccin-mocha"

# herdr: the built-in theme its UI uses for this palette. "terminal" takes
# the terminal's own colors, for palettes herdr has no theme of its own for.
HERDR_THEME="catppuccin"
