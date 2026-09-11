#!/usr/bin/env bash

# Optional Neovim with Omaccy's AstroNvim config.
# Sourced by the entry points; loading this file performs no system changes.
#
# An editor config is where people keep years of their own work, so unlike the
# rest of setup this is opt-in: asked once, after the setup confirmation, and
# remembered in ~/.omaccy/neovim as on or off so updates do not ask again.
# OMACCY_ASSUME_YES never answers it -- an unattended run is agreement to set
# up Omaccy, not to move someone's ~/.config/nvim aside.

neovim_pref_file() {
  printf '%s\n' "$OMACCY_DIR/neovim"
}

neovim_enabled() {
  [[ "$(head -n 1 "$(neovim_pref_file)" 2>/dev/null | tr -d '[:space:]')" == on ]]
}

decide_neovim_setup() {
  local pref
  pref="$(neovim_pref_file)"
  [[ -f "$pref" ]] && return 0

  if [[ "${OMACCY_ASSUME_YES:-0}" == "1" ]]; then
    echo "Skipping the optional Neovim setup: OMACCY_ASSUME_YES does not opt in to replacing ~/.config/nvim."
    echo "Run setup without it to be asked."
    return 0
  fi

  echo ""
  echo "Optional: Neovim with Omaccy's AstroNvim config."
  echo "  - Installs Neovim and ripgrep with Homebrew if missing."
  if [[ -e "$HOME/.config/nvim" || -L "$HOME/.config/nvim" ]]; then
    echo "  - Moves your current ~/.config/nvim to $BAK_DIR and links Omaccy's config in its place;"
    echo "    uninstall puts yours back."
  else
    echo "  - Links Omaccy's config at ~/.config/nvim."
  fi
  echo "  - Plugins download the first time you start nvim. Plugin data in ~/.local/share/nvim is left alone."
  if ask_confirmation "Set up Neovim?"; then
    echo on > "$pref"
  else
    echo off > "$pref"
    echo "Skipping Neovim. To be asked again, delete $pref and rerun setup."
  fi
}

install_neovim() {
  neovim_enabled || return 0
  ensure_formula neovim
  ensure_formula ripgrep
  ensure_dir_symlink "$REPO_ROOT/config/nvim" "$HOME/.config/nvim"
}

# lazy.nvim writes lazy-lock.json into the config directory, so it is the
# plugin manager's file rather than an edit, and does not keep the config.
uninstall_neovim_config() {
  restore_target "$HOME/.config/nvim" "$CONF_DIR/nvim"
  remove_canonical_dir nvim lazy-lock.json
  rm -f "$(neovim_pref_file)"
}
