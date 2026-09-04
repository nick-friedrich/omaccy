#!/usr/bin/env bash
set -u

current="$(defaults read com.apple.dock autohide 2>/dev/null || printf 'false')"
case "$current" in
  1|true|TRUE|yes|YES) next=false ;;
  *) next=true ;;
esac

defaults write com.apple.dock autohide -bool "$next"
killall Dock 2>/dev/null || true
