#!/usr/bin/env bash
# Cross-compile steam_stub.exe from the steam_stub.c beside this script.
#
# The stub is a Win32 GUI program the Ragnarok client expects to find running in
# place of Steam, so it has to come out as a 32-bit PE — which needs a Windows
# cross-compiler, not the system clang. The mingw-w64 toolchain Homebrew ships
# links against the UCRT and pulls in no runtime DLL of its own, so the binary
# it produces needs nothing beside it inside the prefix.
#
# The .exe is not checked in: build.sh compiles it straight into the app bundle,
# so what ships is always what this source says. Run on its own it writes to
# .build, which is only useful for checking that the stub still compiles.
#
#     build.sh                 build into .build/steam_stub/
#     build.sh --output PATH   build to PATH — where build.sh puts it in the app
#     build.sh --check         check the toolchain and stop
#     build.sh --install       install the toolchain with Homebrew first
#
# STEAM_STUB_CC names a cross-compiler other than the default.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
source_file="$script_dir/steam_stub.c"
output_file="$repo_root/.build/steam_stub/steam_stub.exe"

# The i686 compiler, not the x86_64 one: the client loads a 32-bit process.
cc="${STEAM_STUB_CC:-i686-w64-mingw32-gcc}"
formula="mingw-w64"

check_only=0
install_toolchain=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || { echo "Usage: $0 [--output PATH] [--check] [--install]" >&2; exit 1; }
      output_file="$2"
      shift 2
      ;;
    --check)   check_only=1; shift ;;
    --install) install_toolchain=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--output PATH] [--check] [--install]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$install_toolchain" == 1 ]] && ! command -v "$cc" >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 || {
    echo "Homebrew not found — install it from https://brew.sh, or install $formula by hand" >&2
    exit 1
  }
  echo "==> installing $formula"
  brew install "$formula"
fi

command -v "$cc" >/dev/null 2>&1 || {
  echo "error: Windows cross-compiler not found: $cc" >&2
  echo "       every build compiles the Steam stub, so this is needed to build the app." >&2
  echo "       run 'make steam-stub-toolchain' to install it, or 'brew install $formula'." >&2
  echo "       STEAM_STUB_CC=<compiler> names a different one." >&2
  exit 1
}

if [[ "$check_only" == 1 ]]; then
  exit 0
fi

[[ -f "$source_file" ]] || { echo "error: $source_file not found" >&2; exit 1; }

# -mwindows keeps the console window from appearing behind the game, -s drops
# the symbols the stub has no use for, and -static-libgcc keeps a toolchain
# that would otherwise want libgcc_s beside the .exe from doing so.
#
# --no-insert-timestamp leaves the PE header's timestamp field zeroed, so the
# same source and compiler give the same bytes every time — worth having for a
# binary that ships inside a signed bundle.
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/steam-stub-build.XXXXXX")"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

"$cc" -O2 -mwindows -s -static-libgcc -Wl,--no-insert-timestamp \
  -o "$work_dir/steam_stub.exe" "$source_file"

# A native binary here would leave the client with nothing to talk to, and the
# failure would only turn up on someone else's machine.
description="$(file -b "$work_dir/steam_stub.exe")"
case "$description" in
  *"PE32 executable"*"80386"*) ;;
  *)
    echo "error: built a $description, expected a 32-bit PE" >&2
    exit 1
    ;;
esac

mkdir -p "$(dirname "$output_file")"
mv "$work_dir/steam_stub.exe" "$output_file"

echo "    $description"
echo "    sha256: $(shasum -a 256 "$output_file" | awk '{print $1}')"
