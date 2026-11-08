#!/usr/bin/env bash
# Update the pinned MoltenVK to the latest release, or to --tag TAG.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
manifest="$repo_root/Packaging/WineRuntime/runtime-lock.json"
tag=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 ]] || { echo "Usage: $0 [--tag TAG]" >&2; exit 1; }
      tag="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--tag TAG]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

for command in curl jq python3 shasum; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

[[ -f "$manifest" ]] || {
  echo "Runtime lock manifest not found: $manifest" >&2
  exit 1
}

repository="$(jq -er '.moltenvk.repository | strings' "$manifest")"
asset_name="$(jq -er '.moltenvk.asset | strings' "$manifest")"
current_version="$(jq -r '.moltenvk.version // ""' "$manifest")"

if [[ -n "$tag" ]]; then
  api_url="https://api.github.com/repos/$repository/releases/tags/$tag"
else
  api_url="https://api.github.com/repos/$repository/releases/latest"
fi

release_json="$(curl -fsSL "$api_url")"
release_tag="$(jq -r '.tag_name' <<<"$release_json")"
asset_url="$(jq -r --arg name "$asset_name" \
  '.assets[] | select(.name == $name) | .browser_download_url' <<<"$release_json")"
asset_digest="$(jq -r --arg name "$asset_name" \
  '.assets[] | select(.name == $name) | .digest' <<<"$release_json")"
expected_asset_sha256="${asset_digest#sha256:}"

[[ -n "$asset_url" && "$asset_url" != "null" ]] || {
  echo "Release $release_tag does not contain $asset_name" >&2
  exit 1
}
[[ "$expected_asset_sha256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "Release $release_tag does not publish a valid SHA-256 digest" >&2
  exit 1
}

echo "Updating MoltenVK: ${current_version:-<unset>} -> $release_tag"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/moltenvk-update.XXXXXX")"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

archive="$work_dir/$asset_name"
curl -fL --retry 3 --retry-all-errors --progress-bar -o "$archive" "$asset_url"

actual_asset_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
[[ "$actual_asset_sha256" == "$expected_asset_sha256" ]] || {
  echo "Asset checksum mismatch: expected $expected_asset_sha256, got $actual_asset_sha256" >&2
  exit 1
}

"$script_dir/prepare-moltenvk.sh" \
  --archive "$archive" \
  --work "$work_dir/prepare" \
  --output "$work_dir/libMoltenVK.dylib"
dylib_sha256="$(shasum -a 256 "$work_dir/libMoltenVK.dylib" | awk '{print $1}')"

python3 - "$manifest" "$release_tag" "$actual_asset_sha256" "$dylib_sha256" <<'PYEOF'
import json
import pathlib
import sys

path, version, asset_sha256, dylib_sha256 = sys.argv[1:]
manifest = pathlib.Path(path)
data = json.loads(manifest.read_text())

data["moltenvk"]["version"] = version
data["moltenvk"]["assetSha256"] = asset_sha256
for entry in data["overlays"]["external"]:
    if entry["source"] == "libMoltenVK.dylib":
        entry["sha256"] = dylib_sha256

manifest.write_text(json.dumps(data, indent=2) + "\n")
PYEOF

echo "Pinned MoltenVK $release_tag"
echo "  asset: $actual_asset_sha256"
echo "  dylib: $dylib_sha256"
echo
echo "The runtime carries it once it is rebuilt: make runtime, then"
echo "make release-runtime. Give runtime-lock.json a new runtimeRevision first."
