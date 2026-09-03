#!/usr/bin/env bash

state_dir="$HOME/.omaccy"
native_marker="$state_dir/native-menu-visible"

mkdir -p "$state_dir"

if [[ -f "$native_marker" ]]; then
  rm -f "$native_marker"
  sketchybar --bar hidden=off
else
  touch "$native_marker"
  sketchybar --bar hidden=on
fi
