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
  if ! neovim_enabled; then
    # A no after a yes -- from scripts/neovim.sh, or from editing the answer
    # by hand. Leaving the link would strand ~/.config/nvim on Omaccy's config
    # with no way back, so setup takes it out instead of skipping the step.
    if [[ -L "$HOME/.config/nvim" && "$(readlink "$HOME/.config/nvim")" == "$CONF_DIR/nvim" ]]; then
      echo "The Neovim setup is off; restoring your own ~/.config/nvim."
      restore_neovim_config
    fi
    return 0
  fi
  ensure_formula neovim
  ensure_formula ripgrep
  ensure_dir_symlink "$REPO_ROOT/config/nvim" "$HOME/.config/nvim"
}

# Turning the setup off keeps the recorded no, so the next update neither
# relinks the config nor asks again; uninstall forgets the answer as well,
# which is why restoring and forgetting are separate.
#
# lazy.nvim writes lazy-lock.json into the config directory, so it is the
# plugin manager's file rather than an edit, and does not keep the config.
restore_neovim_config() {
  restore_target "$HOME/.config/nvim" "$CONF_DIR/nvim"
  remove_canonical_dir nvim lazy-lock.json
}

uninstall_neovim_config() {
  restore_neovim_config
  rm -f "$(neovim_pref_file)"
}

# The switch behind scripts/neovim.sh: on links Omaccy's config and installs
# what it needs, off puts the user's own back. Neovim and ripgrep are left
# installed either way -- removing packages is uninstall's business, and they
# may well have been there first.
set_neovim_setup() {
  local state="$1"
  mkdir -p "$OMACCY_DIR"
  printf '%s\n' "$state" > "$(neovim_pref_file)"
  if [[ "$state" == on ]]; then
    install_neovim
    echo "Neovim uses Omaccy's config at ~/.config/nvim."
  else
    restore_neovim_config
    echo "Neovim keeps your own config. Neovim and ripgrep stay installed."
  fi
}
