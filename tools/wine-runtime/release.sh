#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: release.sh [--runtime PATH] [--repository OWNER/REPO]

Packages the runtime (package.sh, which pins the archive in
artifact-lock.json) and publishes it as the GitHub release that lock names, at
the commit checked out here, which must already be pushed. --repository
defaults to victormlourenco/ROSilicon. Commit artifact-lock.json afterwards:
that is what points make restore, and the next build, at the release.
EOF
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
manifest="$repo_root/Packaging/WineRuntime/runtime-lock.json"
artifact_lock="$repo_root/Packaging/WineRuntime/artifact-lock.json"
output_dir="$repo_root/.build/runtime-artifacts"
runtime="$repo_root/.wine-runtime"
repository="victormlourenco/ROSilicon"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime)
      [[ $# -ge 2 ]] || usage
      runtime="$2"
      shift 2
      ;;
    --repository)
      [[ $# -ge 2 ]] || usage
      repository="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

for command in gh git jq; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required release command not found: $command" >&2
    exit 1
  }
done

commit="$(git -C "$repo_root" rev-parse HEAD)"
[[ -n "$(git -C "$repo_root" branch -r --contains "$commit")" ]] || {
  echo "Push $commit first: the release is tagged at it." >&2
  exit 1
}

# Refused before packaging, which rewrites artifact-lock.json.
tag="wine-runtime-r$(jq -er '.runtimeRevision | numbers' "$manifest")"
if gh release view "$tag" --repo "$repository" >/dev/null 2>&1; then
  echo "$repository already has a release $tag; bump runtimeRevision in $manifest." >&2
  exit 1
fi

"$script_dir/package.sh" --runtime "$runtime" --output-dir "$output_dir" --repository "$repository"

asset="$(jq -er '.asset | strings' "$artifact_lock")"
wine="$(jq -er '.wine.repository + " " + .wine.commit' "$manifest")"
gh release create "$tag" "$output_dir/$asset" "$output_dir/$asset.sha256" \
  --repo "$repository" \
  --target "$commit" \
  --title "Wine runtime ${tag#wine-runtime-}" \
  --notes "Built from $wine with Packaging/WineRuntime/patches at $commit."

echo "Released $tag. Commit $artifact_lock to point make restore at it."
