#!/usr/bin/env bash

# Homebrew installation, dependency ownership, and optional removal.
# Sourced by the entry points; loading this file performs no system changes.

ensure_brew() {
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  echo "Homebrew not found — installing..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    echo "ERROR: Homebrew installation failed." >&2
    exit 1
  fi
}

record_dep() {
  local marker="$1"
  local cask="$2"
  touch "$OMACCY_DIR/$marker"
  grep -qx "$cask" "$OMACCY_DIR/$marker" || echo "$cask" >> "$OMACCY_DIR/$marker"
}

ensure_cask() {
  local cask="$1"
  local install_ref="${2:-$cask}"
  ensure_brew

  if brew list --cask "$cask" >/dev/null 2>&1; then
    if [[ -f "$OMACCY_DIR/installed-deps" ]] && grep -qx "$cask" "$OMACCY_DIR/installed-deps"; then
      echo "$cask already installed by Omaccy."
    else
      record_dep preinstalled-deps "$cask"
      echo "$cask already installed; Omaccy will leave it installed on uninstall."
    fi
    return
  fi

  echo "Installing $cask..."
  brew install --cask "$install_ref"
  record_dep installed-deps "$cask"
}

ensure_formula() {
  local formula="$1"
  local install_ref="${2:-$formula}"
  ensure_brew

  if brew list --formula "$formula" >/dev/null 2>&1; then
    if [[ -f "$OMACCY_DIR/installed-formulas" ]] && grep -qx "$formula" "$OMACCY_DIR/installed-formulas"; then
      echo "$formula already installed by Omaccy."
    else
      record_dep preinstalled-formulas "$formula"
      echo "$formula already installed; Omaccy will leave it installed on uninstall."
    fi
    return
  fi

  echo "Installing $formula..."
  brew install "$install_ref"
  record_dep installed-formulas "$formula"
}

remove_owned_cask() {
  local cask="$1"
  local display_name="$2"
  local marker="$OMACCY_DIR/installed-deps"
  [[ -f "$marker" ]] && grep -qx "$cask" "$marker" || return 0

  if ask_confirmation "Remove $display_name, which Omaccy installed?"; then
    brew uninstall --cask "$cask" || true
    local updated_marker="$OMACCY_DIR/installed-deps.updated"
    grep -vx "$cask" "$marker" > "$updated_marker" || true
    mv "$updated_marker" "$marker"
    echo "Removed Omaccy-installed $display_name."
  else
    echo "Keeping $display_name installed."
  fi
}

remove_owned_formula() {
  local formula="$1"
  local display_name="$2"
  local marker="$OMACCY_DIR/installed-formulas"
  [[ -f "$marker" ]] && grep -qx "$formula" "$marker" || return 0

  if ask_confirmation "Remove $display_name, which Omaccy installed?"; then
    brew uninstall "$formula" || true
    local updated_marker="$OMACCY_DIR/installed-formulas.updated"
    grep -vx "$formula" "$marker" > "$updated_marker" || true
    mv "$updated_marker" "$marker"
    echo "Removed Omaccy-installed $display_name."
  else
    echo "Keeping $display_name installed."
  fi
}
