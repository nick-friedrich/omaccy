#!/usr/bin/env bash

# SF Pro, installed without sudo. Sourced by the entry points; loading this
# file performs no system changes.
#
# macOS does not ship SF Pro as an installable family, and the SF Symbols
# glyphs SketchyBar draws exist only there, so a machine without it shows a bar
# with blank gaps. Homebrew's font-sf-pro cask would fix that but its artifact
# is a system-domain .pkg, which would put a password prompt in the middle of
# an installer that otherwise never needs one. Apple's own disk image can be
# expanded and copied into ~/Library/Fonts entirely as the user instead, which
# is where Omaccy's other font casks already land.

SF_PRO_URL="https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg"
# The one file that matters: a variable font whose family really is "SF Pro"
# with a Semibold instance, which is what the SketchyBar config asks for. The
# 45 static Display/Text/Rounded faces beside it are different families and
# would only clutter the user's font book.
SF_PRO_FILE="SF-Pro.ttf"

sf_pro_font_dir() {
  printf '%s' "$HOME/Library/Fonts"
}

# Prints where SF Pro already lives, or nothing. Any domain counts: a machine
# that installed it system-wide needs nothing from us.
sf_pro_installed_path() {
  local dir
  for dir in "$HOME/Library/Fonts" /Library/Fonts /System/Library/Fonts; do
    if [[ -f "$dir/$SF_PRO_FILE" ]]; then
      printf '%s' "$dir/$SF_PRO_FILE"
      return 0
    fi
  done
  return 1
}

# Never fatal. The SketchyBar config falls back to plain Unicode glyphs, so a
# failed download costs the nicer icons and nothing else.
sf_pro_unavailable() {
  echo "Skipping SF Pro: $1." >&2
  echo "SketchyBar will draw plain Unicode icons instead. To add it later:" >&2
  printf '  brew install --cask font-sf-pro   (asks for your password)\n' >&2
  return 0
}

ensure_sf_pro_font() {
  local existing tmp_dir mount_dir pkg payload

  if existing="$(sf_pro_installed_path)"; then
    if [[ -f "$OMACCY_DIR/installed-fonts" ]] && grep -qx "$SF_PRO_FILE" "$OMACCY_DIR/installed-fonts"; then
      echo "SF Pro already installed by Omaccy."
    else
      record_dep preinstalled-fonts "$SF_PRO_FILE"
      echo "SF Pro already installed at $existing; Omaccy will leave it in place."
    fi
    return 0
  fi

  echo "Installing SF Pro for the menu bar icons (no password needed)..."
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/omaccy-sfpro.XXXXXX")"
  mount_dir="$tmp_dir/mnt"

  if ! curl -fsSL "$SF_PRO_URL" -o "$tmp_dir/SF-Pro.dmg"; then
    rm -rf "$tmp_dir"
    sf_pro_unavailable "Apple's font download could not be reached"
    return 0
  fi
  if ! hdiutil attach -nobrowse -readonly -mountpoint "$mount_dir" "$tmp_dir/SF-Pro.dmg" >/dev/null 2>&1; then
    rm -rf "$tmp_dir"
    sf_pro_unavailable "the downloaded disk image could not be opened"
    return 0
  fi

  pkg="$(find "$mount_dir" -maxdepth 1 -name "*.pkg" | head -n 1)"
  if [[ -n "$pkg" ]] && pkgutil --expand-full "$pkg" "$tmp_dir/expanded" >/dev/null 2>&1; then
    payload="$(find "$tmp_dir/expanded" -name "$SF_PRO_FILE" | head -n 1)"
  fi
  hdiutil detach "$mount_dir" >/dev/null 2>&1 || true

  if [[ -z "${payload:-}" ]]; then
    rm -rf "$tmp_dir"
    sf_pro_unavailable "Apple's package did not contain $SF_PRO_FILE"
    return 0
  fi

  mkdir -p "$(sf_pro_font_dir)"
  cp "$payload" "$(sf_pro_font_dir)/$SF_PRO_FILE"
  rm -rf "$tmp_dir"
  record_dep installed-fonts "$SF_PRO_FILE"
  echo "Installed SF Pro → $(sf_pro_font_dir)/$SF_PRO_FILE"
}

remove_owned_sf_pro_font() {
  local marker="$OMACCY_DIR/installed-fonts"
  [[ -f "$marker" ]] && grep -qx "$SF_PRO_FILE" "$marker" || return 0

  if ask_confirmation "Remove SF Pro, which Omaccy installed?"; then
    rm -f "$(sf_pro_font_dir)/$SF_PRO_FILE"
    local updated="$marker.updated"
    grep -vx "$SF_PRO_FILE" "$marker" > "$updated" || true
    mv "$updated" "$marker"
    echo "Removed Omaccy-installed SF Pro."
  else
    echo "Keeping SF Pro installed."
  fi
}
