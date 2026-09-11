# Omaccy's zsh setup, loaded from the marked block at the end of ~/.zshrc.
#
# Every part checks first and steps aside when your own config already sets
# the same thing up -- the block runs last, so it can see what loaded before
# it. A prompt of your own (oh-my-posh, p10k, Starship, or anything written by
# hand) keeps Omaccy's Starship out unless you chose Omaccy's during setup, and
# a plugin you already load is not loaded twice, which would slow the shell
# and garble what it draws. Only
# generic defaults live here: nothing machine-specific and no PATH entries.
# Edit freely; updates keep an edited copy of this file.

[[ -o interactive ]] || return 0

_omaccy_dir=${OMACCY_DIR:-$HOME/.omaccy}
_omaccy_brew=${HOMEBREW_PREFIX:-/opt/homebrew}

# History shared between open terminals, without duplicates.
(( HISTSIZE < 50000 )) && HISTSIZE=50000
(( SAVEHIST < 50000 )) && SAVEHIST=50000
setopt share_history hist_ignore_all_dups hist_ignore_space hist_reduce_blanks

# Programs started from the shell (git commit, crontab -e) read EDITOR from the
# environment, so an EDITOR that was set but never exported does not reach them.
[[ -z $EDITOR ]] && (( $+commands[nvim] )) && EDITOR=nvim
[[ -n $EDITOR ]] && export EDITOR

# Option+Left and Option+Right move by word, as in every other macOS text
# field. Ghostty sends these unless its Option key is set to act as Alt.
bindkey '^[[1;3D' backward-word
bindkey '^[[1;3C' forward-word

# zsh-autosuggestions: the rest of a command from your history, as you type.
if (( ! $+functions[_zsh_autosuggest_start] )) &&
    [[ -r $_omaccy_brew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source $_omaccy_brew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# fzf: Ctrl-R searches history, Ctrl-T files, Alt-C directories.
if (( ! $+functions[fzf-history-widget] && $+commands[fzf] )); then
  source <(fzf --zsh)
fi

# zoxide: `z part` jumps to the most used directory matching it.
if (( ! $+functions[__zoxide_z] && $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

# Starship, in the Omaccy theme's colors. Before each prompt STARSHIP_CONFIG is
# pointed at a copy of starship.toml whose [palettes.omaccy] table holds the
# current theme's colors, written the first time a theme is used and again
# whenever the template or the theme file is newer. theme.sh and the launcher
# both write ~/.omaccy/theme, so every open terminal follows a switch on its
# next prompt -- custom themes included, since the colors come from the theme
# file itself.
_omaccy_starship_write() {
  local template=$1 theme_file=$2 config=$3 line key
  local -A colors
  [[ -r $template && -r $theme_file ]] || return 1
  while IFS= read -r line; do
    if [[ $line =~ '^(ACCENT|TEXT|MUTED|OK|DANGER)=0x[[:xdigit:]]{2}([[:xdigit:]]{6})' ]]; then
      colors[${(L)match[1]}]="#${(L)match[2]}"
    fi
  done < $theme_file
  (( ${#colors} == 5 )) || return 1
  mkdir -p ${config:h} || return 1
  {
    while IFS= read -r line; do
      [[ $line == '[palettes.omaccy]'* ]] && break
      print -r -- $line
    done < $template
    print -r -- '[palettes.omaccy]'
    for key in accent text muted ok danger; do
      print -r -- "$key = \"$colors[$key]\""
    done
  } > $config.$$ && mv -f $config.$$ $config
}

_omaccy_starship_theme() {
  local theme template=$_omaccy_dir/config/zsh/starship.toml
  { read -r theme < $_omaccy_dir/theme } 2>/dev/null
  theme=${theme//[[:space:]]/}
  [[ -n $theme ]] || theme=catppuccin
  local theme_file=$_omaccy_dir/config/sketchybar/themes/$theme.sh
  local config=$_omaccy_dir/cache/starship/$theme.toml
  if [[ ! -f $config || $template -nt $config || $theme_file -nt $config ]]; then
    if ! _omaccy_starship_write $template $theme_file $config; then
      export STARSHIP_CONFIG=$template
      return
    fi
  fi
  export STARSHIP_CONFIG=$config
}

# A prompt of your own keeps Starship out: a PROMPT other than zsh's stock one
# (macOS's /etc/zshrc sets '%n@%m %1~ %# ', zsh on its own '%m%# '), or a
# prompt framework's redraw hook. oh-my-posh sets PS1 from its precmd hook
# rather than when it loads, so its PROMPT still looks stock at this point and
# only the hook gives it away. If you chose Omaccy's prompt during setup
# (~/.omaccy/zsh-prompt), those hooks are taken out instead -- left in, they
# would draw their prompt back over Starship before every command.
_omaccy_prompt_hooks='(_omp_*|_p9k_*|prompt_*_precmd|prompt_*_preexec|_powerline*)'
_omaccy_prompt_choice=
{ read -r _omaccy_prompt_choice < $_omaccy_dir/zsh-prompt } 2>/dev/null
_omaccy_other_prompt=(${(M)precmd_functions:#${~_omaccy_prompt_hooks}})
_omaccy_use_starship=0
if [[ $_omaccy_prompt_choice == starship ]]; then
  precmd_functions=(${precmd_functions:#${~_omaccy_prompt_hooks}})
  preexec_functions=(${preexec_functions:#${~_omaccy_prompt_hooks}})
  _omaccy_use_starship=1
elif (( ! ${#_omaccy_other_prompt} )) && [[ $PROMPT == '%n@%m %1~ %# ' || $PROMPT == '%m%# ' ]]; then
  _omaccy_use_starship=1
fi
if (( _omaccy_use_starship && $+commands[starship] )); then
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _omaccy_starship_theme
  _omaccy_starship_theme
  eval "$(starship init zsh)"
fi
unset _omaccy_prompt_hooks _omaccy_prompt_choice _omaccy_other_prompt _omaccy_use_starship

# zsh-syntax-highlighting wraps every widget defined before it, so it has to
# come last.
if (( ! $+functions[_zsh_highlight] )) &&
    [[ -r $_omaccy_brew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source $_omaccy_brew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
