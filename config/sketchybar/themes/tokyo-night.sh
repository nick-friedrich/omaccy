#!/usr/bin/env bash

# Tokyo Night (dark).

BAR_BG=0xff16161e      # bg_dark
ITEM_BG=0xff1a1b26     # background
BORDER=0xff292e42      # bg_highlight
ACCENT=0xff7aa2f7      # blue
TEXT=0xffc0caf5        # foreground
MUTED=0xff565f89       # comment
OK=0xff9ece6a          # green
DANGER=0xfff7768e      # red

# Ghostty ships this palette as a built-in theme name.
GHOSTTY_THEME="TokyoNight Night"

# Whether this is a light or a dark palette. Drives the macOS appearance when
# that switch is on, and nothing otherwise.
APPEARANCE="dark"

# VS Code and Cursor: the marketplace extension shipping this palette, and the
# theme label it contributes. An empty VSCODE_EXTENSION means VS Code has the
# label built in, so nothing needs installing.
VSCODE_EXTENSION="enkia.tokyo-night"
VSCODE_THEME="Tokyo Night"

# Neovim: the colorscheme config/nvim/lua/plugins/omaccy-theme.lua installs
# for this palette. Running nvim instances switch to it as the theme changes.
NVIM_COLORSCHEME="tokyonight-night"

# herdr: the built-in theme its UI uses for this palette. "terminal" takes
# the terminal's own colors, for palettes herdr has no theme of its own for.
HERDR_THEME="tokyo-night"
