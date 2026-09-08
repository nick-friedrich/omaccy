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

# Registers a formula's Homebrew service so it starts at login.
#
# A daemon that is already running outside launchd holds whatever socket or
# port it binds, so launchctl's bootstrap fails (exit 5, and `brew services
# list` then reports "error") even though the program itself is working fine.
# herdr does exactly this when it is already hosting agent sessions. Only
# login-time auto-start is at stake there, so that case is reported as the
# non-problem it is instead of a wall of failure output people read as a
# broken install. Assumes the process is named after the formula, which holds
# for the services Omaccy registers.
ensure_login_service() {
  local formula="$1"
  local output=""

  if output="$(brew services start "$formula" 2>&1)"; then
    [[ -n "$output" ]] && echo "$output"
    return 0
  fi

  if pgrep -x "$formula" >/dev/null 2>&1; then
    echo "$formula is already running, so it could not also be registered to start at login."
    echo "This is not a problem: Omaccy uses the running $formula. To register it later,"
    echo "quit $formula and run: brew services start $formula"
    return 0
  fi

  echo "$output" >&2
  echo "Warning: could not register $formula's login service, and $formula is not running." >&2
  echo "Omaccy still works; start it by hand with: brew services start $formula" >&2
  return 0
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
