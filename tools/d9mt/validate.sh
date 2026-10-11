#!/usr/bin/env bash
# Check a staged d9mt before it goes into the app.
#
#     validate.sh --d9mt PATH
#
# Three things can be checked from outside, and all three are failures nobody
# would notice at the right moment:
#
#   * The machine each piece is for. d9mt is three architectures at once — an
#     i686 PE the 32-bit client loads, an x86_64 PE for 64-bit programs in the
#     prefix, and an x86_64 Mach-O for Wine's unix side, which runs under
#     Rosetta. A piece built for the wrong one loads nowhere, and Wine then
#     falls back to its own D3D9: playable, slow, silent.
#   * That d3d9.dll exports what the client resolves.
#   * That the bridge is complete. d3d9.dll calls Metal through winemetal and
#     compiles shaders through d9mtair, each a PE/unixlib pair, and a d3d9.dll
#     whose bridge is missing loads fine and dies on its first draw.
#
# What cannot be checked here: whether the unixlib ABI these were compiled for
# matches the Wine the app ships. Upstream builds them against CrossOver's
# tree. See docs/d9mt.md.
set -euo pipefail

usage() {
  echo "Usage: $0 --d9mt PATH" >&2
  exit 1
}

d9mt=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --d9mt)
      [[ $# -ge 2 ]] || usage
      d9mt="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$d9mt" ]] || usage

for command in file shasum strings; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required validation command not found: $command" >&2
    exit 1
  }
done

[[ -d "$d9mt" ]] || {
  echo "No staged d9mt at $d9mt" >&2
  echo "Run 'make d9mt D9MT_SOURCE=<d9mt-v2 checkout>' to stage one." >&2
  exit 1
}

# path <TAB> what `file -b` has to say about it. The glob patterns are what
# distinguish the three machines; anything else is the wrong one.
expected=(
  "d3d9.dll"$'\t'"*PE32 executable*DLL*80386*"
  "wine/i386-windows/winemetal.dll"$'\t'"*PE32 executable*DLL*80386*"
  "wine/i386-windows/d9mtair.dll"$'\t'"*PE32 executable*DLL*80386*"
  "wine/x86_64-windows/winemetal.dll"$'\t'"*PE32+ executable*DLL*x86-64*"
  "wine/x86_64-windows/d9mtair.dll"$'\t'"*PE32+ executable*DLL*x86-64*"
  "wine/x86_64-unix/winemetal.so"$'\t'"*Mach-O*64-bit*x86_64*"
  "wine/x86_64-unix/d9mtair.so"$'\t'"*Mach-O*64-bit*x86_64*"
)

for entry in "${expected[@]}"; do
  relative="${entry%%$'\t'*}"
  pattern="${entry#*$'\t'}"
  path="$d9mt/$relative"
  [[ -f "$path" ]] || {
    echo "$relative not found: $path" >&2
    echo "Run 'make d9mt D9MT_SOURCE=<d9mt-v2 checkout>' to stage it." >&2
    exit 1
  }
  description="$(file -b "$path")"
  # shellcheck disable=SC2254 # the pattern is meant to glob
  case "$description" in
    $pattern) ;;
    *)
      echo "$relative is a $description, which is the wrong machine for it: $path" >&2
      exit 1
      ;;
  esac
done

# Read the strings once and match in the shell, for the reason tools/d9vk's
# validate.sh spells out: `strings | grep -q` takes SIGPIPE and pipefail then
# reports a found symbol as a failed pipeline.
symbols="$(strings -a "$d9mt/d3d9.dll")"

# The client resolves Direct3DCreate9; DXVK's swapchain path, which d9mt keeps,
# needs the Ex entry point. Matched as whole lines, so Direct3DCreate9On12
# cannot stand in for Direct3DCreate9.
for symbol in Direct3DCreate9 Direct3DCreate9Ex; do
  case $'\n'"$symbols"$'\n' in
    *$'\n'"$symbol"$'\n'*) ;;
    *)
      echo "d3d9.dll does not export $symbol: $d9mt/d3d9.dll" >&2
      exit 1
      ;;
  esac
done

# And that it is d9mt's d3d9.dll rather than a DXVK one staged by mistake: the
# two are the same filename and the same exports, and the only difference
# visible from out here is which DLLs it imports. d9mt reaches Metal through
# winemetal; no DXVK build imports it.
case $'\n'"$symbols"$'\n' in
  *$'\n'"winemetal.dll"$'\n'*) ;;
  *)
    echo "d3d9.dll does not import winemetal.dll, so it is not a d9mt build: $d9mt/d3d9.dll" >&2
    exit 1
    ;;
esac

echo "Validated d9mt at $d9mt"
if [[ -f "$d9mt/staged-lock.json" ]] && command -v python3 >/dev/null 2>&1; then
  python3 -c '
import json, sys
lock = json.load(open(sys.argv[1]))
print("  %s @ %s" % (lock["repository"], lock["commit"][:12]))
' "$d9mt/staged-lock.json"
else
  echo "  staged with no lock beside it, so which d9mt this is was not recorded" >&2
fi
for entry in "${expected[@]}"; do
  relative="${entry%%$'\t'*}"
  echo "  $relative"
  echo "    $(file -b "$d9mt/$relative")"
  echo "    sha256: $(shasum -a 256 "$d9mt/$relative" | awk '{print $1}')"
done
