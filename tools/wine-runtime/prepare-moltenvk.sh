#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: prepare-moltenvk.sh --archive PATH --work PATH --output PATH

Turns a Khronos MoltenVK macOS release tarball into the dylib the runtime
ships: the x86_64 slice of the universal macOS dylib, named
@loader_path/libMoltenVK.dylib and signed ad hoc under a fixed identifier.

Everything below the launcher is x86_64, and Rosetta 2 loads nothing unsigned;
thinning and renaming both invalidate the signature the release carries, so it
is replaced rather than kept. The fixed identifier keeps the result the same
whatever the file is called on the way through, so its checksum can be pinned.
EOF
  exit 1
}

archive=""
work=""
output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      [[ $# -ge 2 ]] || usage
      archive="$2"
      shift 2
      ;;
    --work)
      [[ $# -ge 2 ]] || usage
      work="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || usage
      output="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$archive" && -n "$work" && -n "$output" ]] || usage

[[ -f "$archive" ]] || {
  echo "MoltenVK archive not found: $archive" >&2
  exit 1
}

member="MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib"

rm -rf "$work"
mkdir -p "$work"
tar -xf "$archive" -C "$work" "$member" || {
  echo "MoltenVK archive does not contain $member: $archive" >&2
  exit 1
}

universal="$work/$member"
lipo -info "$universal" | grep -q 'x86_64' || {
  echo "The MoltenVK release dylib has no x86_64 slice: $universal" >&2
  exit 1
}

mkdir -p "$(dirname "$output")"
lipo -thin x86_64 "$universal" -output "$output"
# Quiet: install_name_tool warns that it is invalidating the signature, which
# is the point — codesign puts a fresh one on straight after.
install_name_tool -id @loader_path/libMoltenVK.dylib "$output" 2>/dev/null
chmod 0644 "$output"
codesign --force --sign - --identifier libMoltenVK "$output" 2>/dev/null

codesign --verify "$output" 2>/dev/null || {
  echo "The prepared libMoltenVK.dylib is not signed: $output" >&2
  exit 1
}
