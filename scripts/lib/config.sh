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

# Copy a repository default into ~/.omaccy/config.
# Preserve customized canonical files when refreshing shipped defaults.
install_canonical() {
  local repo_path="$1"
  local rel="${repo_path#"$REPO_ROOT/config/"}"
  local canonical="$CONF_DIR/$rel"

  mkdir -p "$(dirname "$canonical")"

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
}

# Link the consumer's path to a canonical config, backing up what was there.
link_canonical() {
  local canonical="$1"
  local target_path="$2"

  mkdir -p "$(dirname "$target_path")"

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

ensure_symlink() {
  local repo_path="$1"
  local target_path="$2"
  install_canonical "$repo_path"
  link_canonical "$CONF_DIR/${repo_path#"$REPO_ROOT/config/"}" "$target_path"
}

# A tool that reads a whole directory (Neovim) gets one link to the canonical
# directory. Its files are still copied and stamped one by one, so an update
# refreshes the untouched ones and keeps edited ones, and files added later --
# the user's own, or lazy-lock.json -- are never stamped and never replaced.
ensure_dir_symlink() {
  local repo_dir="$1"
  local target_path="$2"
  local file
  # find failing inside the process substitution would not stop the loop, and
  # the link below would then displace the user's config for an empty one.
  if [[ ! -d "$repo_dir" ]]; then
    echo "ERROR: $repo_dir is missing; leaving $target_path as it is." >&2
    return 1
  fi
  while IFS= read -r file; do
    install_canonical "$file"
  done < <(find "$repo_dir" -type f | sort)
  link_canonical "$CONF_DIR/${repo_dir#"$REPO_ROOT/config/"}" "$target_path"
}

# Uninstall's counterpart to ensure_dir_symlink. A config directory can hold
# real work, so it is deleted only while every file in it is an untouched
# default; otherwise it is kept whole in the backups directory, under an
# omaccy- prefix so restore_target never mistakes it for the user's original.
# Further arguments name generated files that do not count as edits.
remove_canonical_dir() {
  local rel="$1"
  shift
  local dir="$CONF_DIR/$rel"
  local file name generated edited=0

  if [[ -d "$dir" ]]; then
    while IFS= read -r file; do
      name="$(basename "$file")"
      for generated in "$@"; do
        [[ "$name" == "$generated" ]] && continue 2
      done
      if ! config_is_pristine "${file#"$CONF_DIR/"}"; then
        edited=1
        break
      fi
    done < <(find "$dir" -type f)

    if [[ "$edited" == 1 ]]; then
      mkdir -p "$BAK_DIR"
      local kept="$BAK_DIR/omaccy-$(printf '%s' "$rel" | tr / -).$(date +%Y%m%d-%H%M%S)"
      mv "$dir" "$kept"
      echo "Kept your edited $rel config → $kept"
    else
      rm -rf "$dir"
    fi
  fi
  rm -rf "$OMACCY_DIR/sha256/$rel"
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

# The master/stack window placement retired in 0.4.2. Its script is gone from
# the checkout, so the symlink an earlier install left in ~/.config would dangle
# and AeroSpace would run nothing on every new window; the canonical copy and
# its checksum go with it. Only a link Omaccy made is touched -- a file the user
# has put there since is left alone, the way restore_target treats one, and a
# canonical copy that was edited is kept in the backups directory rather than
# deleted, since retiring a feature is no reason to discard someone's work.
retire_master_stack_script() {
  local rel="aerospace/master-stack.sh"
  local target="$HOME/.config/$rel"
  local canonical="$CONF_DIR/$rel"

  if [[ -L "$target" && "$(readlink "$target")" == "$canonical" ]]; then
    rm "$target"
    echo "Removed the retired master/stack window placement."
  fi
  if [[ -f "$canonical" ]] && ! config_is_pristine "$rel"; then
    mkdir -p "$BAK_DIR"
    mv "$canonical" "$BAK_DIR/master-stack.sh.$(date +%Y%m%d-%H%M%S)"
    echo "Kept your edited master-stack.sh → $BAK_DIR"
  fi
  rm -f "$canonical" "$OMACCY_DIR/sha256/$rel"
}

# The most recent backup of a target. Directories count: a displaced config can
# be one (~/.config/nvim), not only a file or a link into someone's dotfiles.
latest_backup() {
  local target="$1"
  find "$BAK_DIR" -mindepth 1 -maxdepth 1 \( -type f -o -type l -o -type d \) \
    -name "$(basename "$target").*" -print 2>/dev/null | sort | tail -n 1
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
  backup="$(latest_backup "$target")"
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

  backup="$(latest_backup "$target")"
  if [[ -n "$backup" ]]; then
    mv "$backup" "$target"
    echo "Restored original config → $target"
  fi
}
