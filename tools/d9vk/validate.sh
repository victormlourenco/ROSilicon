#!/usr/bin/env bash
# Check the built d3d9.dll before it goes into the app.
#
# Like the Steam stub, this is cross-compiled, so the interesting failure is a
# binary for the wrong machine: the client is 32-bit and loads d3d9.dll into its
# own address space, so a 64-bit build would simply fail to load and the game
# would fall back to Wine's own D3D9 — slower, and only noticed by whoever runs
# it. The exports are checked too, since a d3d9.dll without Direct3DCreate9 is
# not one the client can use.
set -euo pipefail

usage() {
  echo "Usage: $0 --d9vk PATH" >&2
  exit 1
}

d9vk=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --d9vk)
      [[ $# -ge 2 ]] || usage
      d9vk="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$d9vk" ]] || usage

for command in file shasum strings; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required validation command not found: $command" >&2
    exit 1
  }
done

library="$d9vk/d3d9.dll"
[[ -f "$library" ]] || {
  echo "d3d9.dll not found: $library" >&2
  echo "Run 'make d9vk' to build it." >&2
  exit 1
}

# 32-bit, and a Windows DLL rather than anything the host could load.
description="$(file -b "$library")"
case "$description" in
  *"PE32 executable"*"DLL"*"80386"*) ;;
  *)
    echo "d3d9.dll is a $description, expected a 32-bit PE DLL: $library" >&2
    exit 1
    ;;
esac

# Read the strings once and match in the shell. A `strings | grep -q` pipeline
# would look right and fail here: grep exits on the first hit, strings takes
# SIGPIPE, and pipefail then reports the whole pipeline as failed even though
# the symbol was found.
symbols="$(strings -a "$library")"

# The client resolves both: Ragexe calls Direct3DCreate9, and DXVK's own
# swapchain path needs the Ex entry point. Matched as whole lines, so
# Direct3DCreate9On12 cannot stand in for Direct3DCreate9.
for symbol in Direct3DCreate9 Direct3DCreate9Ex; do
  case $'\n'"$symbols"$'\n' in
    *$'\n'"$symbol"$'\n'*) ;;
    *)
      echo "d3d9.dll does not export $symbol: $library" >&2
      exit 1
      ;;
  esac
done

version=""
while IFS= read -r line; do
  case "$line" in
    DXVK\ v*) version="$line"; break ;;
  esac
done <<< "$symbols"

[[ -n "$version" ]] || {
  echo "d3d9.dll carries no DXVK version string, so it is not a DXVK build: $library" >&2
  exit 1
}

echo "Validated d3d9.dll at $library"
echo "  $description"
echo "  $version"
echo "  sha256: $(shasum -a 256 "$library" | awk '{print $1}')"
