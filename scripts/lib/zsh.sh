#!/usr/bin/env bash

# Optional zsh setup: Omaccy's omaccy.zsh, loaded from a marked block at the
# end of ~/.zshrc, and the tools it sets up.
# Sourced by the entry points; loading this file performs no system changes.
#
# A shell's startup file is the user's own, so Omaccy never replaces it. It
# appends one marked block that sources ~/.omaccy/config/zsh/omaccy.zsh, and
# uninstall removes exactly that block. A ~/.zshrc that is a link -- usually
# into a dotfiles repository -- is only written through once the user says so,
# since that changes their repository; otherwise the block is printed for them
# to add. Like Neovim this is opt-in, asked once and remembered in
# ~/.omaccy/zsh, and OMACCY_ASSUME_YES never answers it or the questions that
# follow, since they change how every terminal starts. It is only offered when
# the login shell is zsh; Omaccy never changes anyone's login shell.

ZSH_SETUP_FORMULAS="starship zoxide fzf zsh-autosuggestions zsh-syntax-highlighting"
ZSH_BLOCK_START="# >>> omaccy >>>"
ZSH_BLOCK_END="# <<< omaccy <<<"

zsh_pref_file() {
  printf '%s\n' "$OMACCY_DIR/zsh"
}

# A remembered answer: zsh (on|off), zshrc-link (write|print), zsh-prompt
# (starship|own).
zsh_answer() {
  head -n 1 "$OMACCY_DIR/$1" 2>/dev/null | tr -d '[:space:]'
}

zsh_enabled() {
  [[ "$(zsh_answer zsh)" == on ]]
}

zshrc_path() {
  printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc"
}

# Where a linked ~/.zshrc points, as an absolute path for the questions and
# messages that name it.
zshrc_target() {
  local zshrc link
  zshrc="$(zshrc_path)"
  link="$(readlink "$zshrc")"
  [[ "$link" == /* ]] || link="$(dirname "$zshrc")/$link"
  printf '%s\n' "$link"
}

zshrc_loads_omaccy() {
  grep -qF '.omaccy/config/zsh/omaccy.zsh' "$(zshrc_path)" 2>/dev/null
}

# The login shell as Directory Services records it. $SHELL would only say what
# started this script. A function of its own so the smoke checks can stand in.
login_shell() {
  dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{print $2}'
}

zsh_block() {
  printf '%s\n' "$ZSH_BLOCK_START" \
    "# Omaccy's zsh setup: prompt, autosuggestions, syntax highlighting, fzf and" \
    "# zoxide, each skipped if this file already sets it up. Keep this block last." \
    '[[ -r "$HOME/.omaccy/config/zsh/omaccy.zsh" ]] && source "$HOME/.omaccy/config/zsh/omaccy.zsh"' \
    "$ZSH_BLOCK_END"
}

# The prompt a ~/.zshrc sets up itself, found by reading it rather than running
# it -- running someone's shell startup has side effects. Comments do not
# count. Prints nothing for zsh's stock prompt. omaccy.zsh checks again when it
# loads, which also catches a prompt set up in a file this one sources.
zshrc_prompt_owner() {
  local code
  code="$(grep -v '^[[:space:]]*#' "$(zshrc_path)" 2>/dev/null)" || return 0
  case "$code" in
    *oh-my-posh*) echo oh-my-posh ;;
    *powerlevel10k*|*p10k*) echo Powerlevel10k ;;
    *"starship init"*) echo Starship ;;
    *oh-my-zsh.sh*)
      grep -qE "^[[:space:]]*ZSH_THEME=(\"\"|'')?[[:space:]]*$" <<< "$code" || echo "an oh-my-zsh theme"
      ;;
    *)
      if grep -qE '^[[:space:]]*(export[[:space:]]+)?(PROMPT|PS1)=' <<< "$code"; then
        echo "a prompt of your own"
      fi
      ;;
  esac
  return 0
}

decide_zsh_setup() {
  local pref shell
  pref="$(zsh_pref_file)"
  if [[ ! -f "$pref" ]]; then
    shell="$(login_shell)"
    if [[ "$(basename "${shell:-unknown}")" != zsh ]]; then
      echo "Skipping the optional zsh setup: your login shell is ${shell:-unknown}, not zsh."
      echo "To use it, switch with 'chsh -s /bin/zsh' and rerun setup."
      return 0
    fi

    if [[ "${OMACCY_ASSUME_YES:-0}" == "1" ]]; then
      echo "Skipping the optional zsh setup: OMACCY_ASSUME_YES does not opt in to changing ~/.zshrc."
      echo "Run setup without it to be asked."
      return 0
    fi

    echo ""
    echo "Optional: Omaccy's zsh setup."
    echo "  - Installs Starship, zoxide, fzf, zsh-autosuggestions, and zsh-syntax-highlighting with Homebrew if missing."
    echo "  - A Starship prompt in the Omaccy theme's colors."
    echo "  - Anything your ~/.zshrc already sets up is left to it."
    if [[ -L "$(zshrc_path)" ]]; then
      echo "  - Your ~/.zshrc is a link to $(zshrc_target); setup asks before adding anything there."
    else
      echo "  - Adds a marked block to the end of ~/.zshrc; uninstall removes it."
    fi
    if ! ask_confirmation "Set up zsh?"; then
      echo off > "$pref"
      echo "Skipping zsh. To be asked again, delete $pref and rerun setup."
      return 0
    fi
    echo on > "$pref"
  fi

  # Asked on later runs too, so someone who said yes before these questions
  # existed still gets them once.
  zsh_enabled || return 0
  decide_zsh_link
  decide_zsh_prompt
}

# Writing through a linked ~/.zshrc changes a file in someone's dotfiles
# repository, which is theirs to allow. Only asked while the link does not
# already load Omaccy.
decide_zsh_link() {
  local zshrc answer_file="$OMACCY_DIR/zshrc-link"
  zshrc="$(zshrc_path)"
  [[ -f "$answer_file" || ! -L "$zshrc" ]] && return 0
  zshrc_loads_omaccy && return 0
  [[ "${OMACCY_ASSUME_YES:-0}" == "1" ]] && return 0

  echo ""
  echo "Your ~/.zshrc is a link to $(zshrc_target)."
  echo "  - Omaccy can add its lines to the end of that file. It lives outside ~/.omaccy,"
  echo "    so commit the change wherever you keep it; uninstall takes the lines out again."
  echo "  - Otherwise setup prints the lines for you to add yourself."
  if ask_confirmation "Add Omaccy's lines to $(zshrc_target)?"; then
    echo write > "$answer_file"
  else
    echo print > "$answer_file"
  fi
}

# A prompt of the user's own keeps Omaccy's Starship out unless they choose
# otherwise here. Their ~/.zshrc is not changed either way: omaccy.zsh reads
# the answer and takes the other prompt's hooks out when it loads.
decide_zsh_prompt() {
  local owner answer_file="$OMACCY_DIR/zsh-prompt"
  [[ -f "$answer_file" ]] && return 0
  owner="$(zshrc_prompt_owner)"
  [[ -n "$owner" ]] || return 0
  [[ "${OMACCY_ASSUME_YES:-0}" == "1" ]] && return 0

  echo ""
  echo "Your ~/.zshrc sets up its own prompt ($owner), so Omaccy's Starship prompt stays out of its way."
  echo "  - Omaccy can use its Starship prompt instead, in the Omaccy theme's colors."
  echo "  - Your ~/.zshrc is not changed. To be asked again, delete $answer_file."
  if ask_confirmation "Use Omaccy's Starship prompt instead of $owner?"; then
    echo starship > "$answer_file"
  else
    echo own > "$answer_file"
  fi
}

install_zsh_setup() {
  if ! zsh_enabled; then
    # A no after a yes -- from scripts/zsh.sh, or from editing the answer by
    # hand. Leaving the block would keep loading Omaccy's setup in every new
    # terminal, so setup takes it out instead of skipping the step.
    if [[ -f "$(zshrc_path)" ]] && grep -qxF "$ZSH_BLOCK_START" "$(zshrc_path)"; then
      echo "The zsh setup is off; taking Omaccy's block back out."
      remove_zshrc_block
    fi
    return 0
  fi
  local formula
  for formula in $ZSH_SETUP_FORMULAS; do
    ensure_formula "$formula"
  done
  install_canonical "$REPO_ROOT/config/zsh/omaccy.zsh"
  install_canonical "$REPO_ROOT/config/zsh/starship.toml"
  add_zshrc_block
}

add_zshrc_block() {
  local zshrc
  zshrc="$(zshrc_path)"

  if zshrc_loads_omaccy; then
    echo "$zshrc already loads Omaccy's zsh setup."
    return 0
  fi

  # A link is written through only with the user's yes, and never while it
  # points nowhere: writing would create a file wherever it happens to point.
  if [[ -L "$zshrc" ]] && [[ "$(zsh_answer zshrc-link)" != write || ! -e "$zshrc" ]]; then
    echo "Your ~/.zshrc is a link to $(zshrc_target), so Omaccy leaves it alone."
    echo "To load Omaccy's zsh setup, add these lines at the end of it:"
    zsh_block | sed 's/^/    /'
    return 0
  fi

  if [[ -e "$zshrc" ]]; then
    if [[ ! -f "$BAK_DIR/omaccy-zshrc.original" ]]; then
      mkdir -p "$BAK_DIR"
      cp "$zshrc" "$BAK_DIR/omaccy-zshrc.original"
    fi
    # A last line without its newline would run into the block.
    if [[ -s "$zshrc" && -n "$(tail -c 1 "$zshrc")" ]]; then
      printf '\n' >> "$zshrc"
    fi
    { printf '\n'; zsh_block; } >> "$zshrc"
  else
    zsh_block > "$zshrc"
    touch "$OMACCY_DIR/zshrc-created"
  fi
  if [[ -L "$zshrc" ]]; then
    echo "Added Omaccy's zsh setup to $(zshrc_target); commit it wherever you keep that file."
  else
    echo "Added Omaccy's zsh setup to $zshrc; new terminals pick it up."
  fi
}

# Takes out the block and the one blank line add_zshrc_block put in front of
# it, so a file that ended in a newline comes back byte for byte. Written
# through with `>`, so the file keeps its permissions and a link stays a link.
remove_zshrc_block() {
  local zshrc stripped
  zshrc="$(zshrc_path)"
  [[ -f "$zshrc" ]] && grep -qxF "$ZSH_BLOCK_START" "$zshrc" || return 0

  if [[ -L "$zshrc" && "$(zsh_answer zshrc-link)" != write ]]; then
    echo "Left in place: $zshrc is a link, so remove the lines from '$ZSH_BLOCK_START' to '$ZSH_BLOCK_END' in $(zshrc_target) yourself."
    return 0
  fi

  stripped="$(awk -v start="$ZSH_BLOCK_START" -v end="$ZSH_BLOCK_END" '
    $0 == start { skipping = 1; held = 0; next }
    skipping { if ($0 == end) skipping = 0; next }
    {
      if (held) print ""
      held = 0
      if ($0 == "") { held = 1; next }
      print
    }
    END { if (held) print "" }
  ' "$zshrc"; printf x)"
  printf '%s' "${stripped%x}" > "$zshrc"

  if [[ ! -L "$zshrc" && -f "$OMACCY_DIR/zshrc-created" ]] && ! grep -q '[^[:space:]]' "$zshrc"; then
    rm -f "$zshrc"
    echo "Removed the ~/.zshrc Omaccy created."
  else
    echo "Removed Omaccy's block from $zshrc."
  fi
  rm -f "$OMACCY_DIR/zshrc-created"
}

# The switch behind scripts/zsh.sh: on adds the block back (installing what it
# needs), off takes it out and leaves the shell as it was before. The tools are
# left installed either way -- removing packages is uninstall's business, and
# fzf or zoxide may well have been there first. The remembered answers to the
# link and prompt questions are kept, so turning it on again does not ask.
set_zsh_setup() {
  local state="$1"
  mkdir -p "$OMACCY_DIR"
  printf '%s\n' "$state" > "$(zsh_pref_file)"
  if [[ "$state" == on ]]; then
    install_zsh_setup
  else
    remove_zshrc_block
    rm -rf "$OMACCY_DIR/cache/starship"
    echo "New terminals start without Omaccy's zsh setup; its tools stay installed."
  fi
}

uninstall_zsh_setup() {
  remove_zshrc_block
  remove_canonical_dir zsh
  rm -rf "$OMACCY_DIR/cache/starship"
  rmdir "$OMACCY_DIR/cache" 2>/dev/null || true
  rm -f "$(zsh_pref_file)" "$OMACCY_DIR/zshrc-link" "$OMACCY_DIR/zsh-prompt"
}
