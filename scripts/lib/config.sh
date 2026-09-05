#!/usr/bin/env bash

# Canonical configs, pristine-file stamps, backups, and restoration.
# Sourced by the entry points; loading this file performs no system changes.

stamp_config() {
  local rel="$1"
  local stamp_file="$OMACCY_DIR/sha256/$rel"
  mkdir -p "$(dirname "$stamp_file")"
  shasum -a 256 "$CONF_DIR/$rel" | awk '{print $1}' > "$stamp_file"
}

config_is_pristine() {
  local rel="$1"
  local stamp_file="$OMACCY_DIR/sha256/$rel"
  [[ -f "$stamp_file" && -f "$CONF_DIR/$rel" ]] || return 1
  [[ "$(cat "$stamp_file")" == "$(shasum -a 256 "$CONF_DIR/$rel" | awk '{print $1}')" ]]
}

# Copy a repository default into ~/.omaccy/config and link the consumer's path.
# Preserve customized canonical files when refreshing shipped defaults.
ensure_symlink() {
  local repo_path="$1"
  local target_path="$2"
  local rel="${repo_path#"$REPO_ROOT/config/"}"
  local canonical="$CONF_DIR/$rel"

  mkdir -p "$(dirname "$canonical")" "$(dirname "$target_path")"

  if [[ ! -e "$canonical" && ! -L "$canonical" ]]; then
    cp "$repo_path" "$canonical"
    stamp_config "$rel"
    echo "Installed canonical config → $canonical"
  elif [[ -L "$canonical" ]]; then
    rm "$canonical"
    cp "$repo_path" "$canonical"
    stamp_config "$rel"
    echo "Re-established canonical config → $canonical"
  elif config_is_pristine "$rel"; then
    if ! cmp -s "$repo_path" "$canonical"; then
      cp "$repo_path" "$canonical"
      stamp_config "$rel"
      echo "Updated canonical config → $canonical"
    fi
  else
    echo "Canonical config customized by user → $canonical (left as-is)"
  fi

  if [[ -L "$target_path" && "$(readlink "$target_path")" == "$canonical" ]]; then
    echo "Already symlinked → $target_path"
    return
  fi

  if [[ -e "$target_path" || -L "$target_path" ]]; then
    local backup="$BAK_DIR/$(basename "$target_path").$(date +%Y%m%d-%H%M%S)"
    mv "$target_path" "$backup"
    echo "Backed up existing $target_path → $backup"
  fi
  ln -s "$canonical" "$target_path"
  echo "Symlinked $target_path → $canonical"
}

# AeroSpace rejects startup if both its legacy and XDG config paths exist.
# Preserve the alternate config here so uninstall can restore it.
ensure_absent_with_backup() {
  local target_path="$1"

  if [[ -e "$target_path" || -L "$target_path" ]]; then
    local backup="$BAK_DIR/$(basename "$target_path").$(date +%Y%m%d-%H%M%S)"
    mv "$target_path" "$backup"
    echo "Backed up conflicting $target_path → $backup"
  fi
}

migrate_legacy_karabiner_config() {
  local old_target="$HOME/.config/karabiner/karabiner.json"
  if [[ -L "$old_target" && "$(readlink "$old_target")" == "$CONF_DIR/karabiner/karabiner.json" ]]; then
    rm "$old_target"
    local backup
    backup="$(find "$BAK_DIR" -maxdepth 1 -type f -name 'karabiner.json.*' -print 2>/dev/null | sort | tail -n 1)"
    if [[ -n "$backup" ]]; then
      mv "$backup" "$old_target"
      echo "Restored pre-Omaccy Karabiner config → $old_target"
    fi
    echo "Removed the retired Omaccy Karabiner mapping."
  fi
}

restore_target() {
  local target="$1"
  local canonical="$2"
  local backup

  if [[ ! -L "$target" || "$(readlink "$target")" != "$canonical" ]]; then
    echo "Not an Omaccy symlink → $target (left as-is)"
    return
  fi

  rm "$target"
  backup="$(find "$BAK_DIR" -maxdepth 1 \( -type f -o -type l \) -name "$(basename "$target").*" -print 2>/dev/null | sort | tail -n 1)"
  if [[ -n "$backup" ]]; then
    mv "$backup" "$target"
    echo "Restored original config → $target"
  else
    echo "Removed Omaccy symlink → $target"
  fi
}

restore_displaced_target() {
  local target="$1"
  local backup

  if [[ -e "$target" || -L "$target" ]]; then
    echo "A new config exists → $target (left as-is)"
    return
  fi

  backup="$(find "$BAK_DIR" -maxdepth 1 \( -type f -o -type l \) -name "$(basename "$target").*" -print 2>/dev/null | sort | tail -n 1)"
  if [[ -n "$backup" ]]; then
    mv "$backup" "$target"
    echo "Restored original config → $target"
  fi
}
