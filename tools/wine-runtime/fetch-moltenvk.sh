#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: fetch-moltenvk.sh --output PATH

Prepares the libMoltenVK.dylib that Packaging/WineRuntime/runtime-lock.json
pins into --output, a directory: downloads the pinned Khronos release asset,
checks it against the lock, takes the x86_64 slice of the macOS dylib, names it
@loader_path/libMoltenVK.dylib and signs it ad hoc. The result is checked
against the lock's overlay checksum, so a tree built here carries the same
MoltenVK as one built anywhere else.

The dylib the build assembles overwrites whichever copy the base runtime
carried, which is how a MoltenVK bump reaches a new runtime.
EOF
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
manifest="$repo_root/Packaging/WineRuntime/runtime-lock.json"
output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
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

[[ -n "$output" ]] || usage

for command in codesign curl install_name_tool jq lipo shasum tar; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

[[ -f "$manifest" ]] || {
  echo "Runtime lock manifest not found: $manifest" >&2
  exit 1
}

version="$(jq -er '.moltenvk.version | strings' "$manifest")"
repository="$(jq -er '.moltenvk.repository | strings' "$manifest")"
asset_name="$(jq -er '.moltenvk.asset | strings' "$manifest")"
expected_asset_sha256="$(jq -er '.moltenvk.assetSha256 | strings' "$manifest")"
expected_dylib_sha256="$(jq -er \
  '.overlays.external[] | select(.source == "libMoltenVK.dylib") | .sha256' "$manifest")"

[[ -n "$expected_dylib_sha256" ]] || {
  echo "The runtime lock has no libMoltenVK.dylib overlay to pin." >&2
  exit 1
}

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/rosilicon-moltenvk.XXXXXX")"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

archive="$work_dir/$asset_name"
echo "Downloading MoltenVK $version from $repository ..."
curl -fL --retry 3 --retry-all-errors --progress-bar \
  -o "$archive" \
  "https://github.com/$repository/releases/download/$version/$asset_name"

actual_asset_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
[[ "$actual_asset_sha256" == "$expected_asset_sha256" ]] || {
  echo "MoltenVK asset checksum mismatch: expected $expected_asset_sha256, got $actual_asset_sha256" >&2
  exit 1
}

"$script_dir/prepare-moltenvk.sh" \
  --archive "$archive" \
  --work "$work_dir/prepare" \
  --output "$output/libMoltenVK.dylib"

actual_dylib_sha256="$(shasum -a 256 "$output/libMoltenVK.dylib" | awk '{print $1}')"
[[ "$actual_dylib_sha256" == "$expected_dylib_sha256" ]] || {
  echo "Prepared libMoltenVK.dylib does not match the lock." >&2
  echo "Expected: $expected_dylib_sha256" >&2
  echo "Actual:   $actual_dylib_sha256" >&2
  echo "The ad hoc signature is the Xcode toolchain's; a mismatch here usually" >&2
  echo "means this Mac's Xcode differs from the one the pin was taken on." >&2
  exit 1
}

echo "Prepared MoltenVK $version at $output/libMoltenVK.dylib"
