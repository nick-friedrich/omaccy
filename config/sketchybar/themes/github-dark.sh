#!/usr/bin/env bash

# GitHub Dark (default).

BAR_BG=0xff0d1117      # canvas.default
ITEM_BG=0xff161b22     # canvas.subtle
BORDER=0xff30363d      # border.default
ACCENT=0xff2f81f7      # accent.fg
TEXT=0xffe6edf3        # fg.default
MUTED=0xff8b949e       # fg.muted
OK=0xff3fb950          # success.fg
DANGER=0xfff85149      # danger.fg

# Ghostty ships this palette as a built-in theme name.
GHOSTTY_THEME="GitHub Dark Default"

# Whether this is a light or a dark palette. Drives the macOS appearance when
# that switch is on, and nothing otherwise.
APPEARANCE="dark"

# VS Code and Cursor: the marketplace extension shipping this palette, and the
# theme label it contributes. An empty VSCODE_EXTENSION means VS Code has the
# label built in, so nothing needs installing.
VSCODE_EXTENSION="GitHub.github-vscode-theme"
VSCODE_THEME="GitHub Dark Default"

# Neovim: the colorscheme config/nvim/lua/plugins/omaccy-theme.lua installs
# for this palette. Running nvim instances switch to it as the theme changes.
NVIM_COLORSCHEME="github_dark_default"

# herdr: the built-in theme its UI uses for this palette. "terminal" takes
# the terminal's own colors, for palettes herdr has no theme of its own for.
HERDR_THEME="terminal"
# herdr's terminal theme leaves its tab bar transparent and draws the active
# tab's number in dark gray on the accent, so set the accent and the panel
# color -- Ghostty's own background -- under [theme.custom].
HERDR_ACCENT="#2f81f7"
HERDR_PANEL_BG="#0d1117"
