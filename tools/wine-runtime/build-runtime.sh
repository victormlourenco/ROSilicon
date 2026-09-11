#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: build-runtime.sh [--output PATH] [--work PATH] [--jobs COUNT]

Builds the runtime Packaging/WineRuntime/runtime-lock.json describes, from
source, on this Mac: restores the runtime artifact-lock.json pins as the base,
fetches the pinned Wine, builds it with the patches (build.sh), assembles the
tree into --output (default .wine-runtime, which must not exist yet) and
validates it. The base lends the new tree its mtld3d and library overlays, and
the x86_64 dylibs configure links against, so each release is built on the
last.

--work holds the base, the source and the build (default
.build/wine-runtime), and is cleared first.
EOF
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
manifest="$repo_root/Packaging/WineRuntime/runtime-lock.json"
output="$repo_root/.wine-runtime"
work="$repo_root/.build/wine-runtime"
jobs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || usage
      output="$2"
      shift 2
      ;;
    --work)
      [[ $# -ge 2 ]] || usage
      work="$2"
      shift 2
      ;;
    --jobs)
      [[ $# -ge 2 ]] || usage
      jobs=(--jobs "$2")
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

# Checked before the build rather than by assemble.sh after it.
[[ ! -e "$output" ]] || {
  echo "Wine runtime destination already exists: $output" >&2
  echo "Move it aside first; the build never overwrites a runtime." >&2
  exit 1
}

rm -rf "$work"
mkdir -p "$work"

"$script_dir/restore.sh" --no-validate --runtime "$work/base"
"$script_dir/fetch-source.sh" --output "$work/source"
"$script_dir/build.sh" \
  --source "$work/source" \
  --build "$work/build" \
  --install "$work/install" \
  --libs "$work/base/lib/external" \
  ${jobs[@]+"${jobs[@]}"}
"$script_dir/assemble.sh" \
  --wine-root "$work/install" \
  --mtld3d-root "$work/base/lib" \
  --external-root "$work/base/lib/external" \
  --output "$output"
"$script_dir/validate.sh" --runtime "$output"

echo "Built Wine runtime r$(jq -r '.runtimeRevision' "$manifest") at $output"
