#!/usr/bin/env bash
# Check the built Steam stub before it goes into the app.
#
# The stub is cross-compiled, so the interesting failure is a binary for the
# wrong machine: a native one would leave the client with nothing to talk to,
# and the failure would only turn up on someone else's machine.
set -euo pipefail

usage() {
  echo "Usage: $0 --stub PATH" >&2
  exit 1
}

stub=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stub)
      [[ $# -ge 2 ]] || usage
      stub="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$stub" ]] || usage

for command in file shasum; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required validation command not found: $command" >&2
    exit 1
  }
done

executable="$stub/steam_stub.exe"
[[ -f "$executable" ]] || {
  echo "Steam stub not found: $executable" >&2
  echo "Run 'make steam-stub' to build it." >&2
  exit 1
}

# 32-bit, and a Windows PE rather than anything the host could run.
description="$(file -b "$executable")"
case "$description" in
  *"PE32 executable"*"80386"*) ;;
  *)
    echo "Steam stub is a $description, expected a 32-bit PE: $executable" >&2
    exit 1
    ;;
esac

# The client starts the stub as a GUI process; a console subsystem binary would
# flash a terminal window over the game.
case "$description" in
  *"(GUI)"*) ;;
  *)
    echo "Steam stub is not a GUI subsystem binary: $executable" >&2
    exit 1
    ;;
esac

echo "Validated Steam stub at $executable"
echo "  $description"
echo "  sha256: $(shasum -a 256 "$executable" | awk '{print $1}')"
