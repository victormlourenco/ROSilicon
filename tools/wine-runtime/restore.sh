#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: restore.sh [--runtime PATH] [--repository OWNER/REPO] [--no-validate]

Fetches the runtime artifact-lock.json pins from the GitHub releases of the
repository it names, and checks it against the lock.

--no-validate skips validate.sh, for a runtime restored only as the base of
the next build: its embedded runtime lock predates the one in this checkout.
EOF
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
artifact_lock="$repo_root/Packaging/WineRuntime/artifact-lock.json"
runtime="$repo_root/.wine-runtime"
repository=""
validate=1

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
    --no-validate)
      validate=0
      shift
      ;;
    *)
      usage
      ;;
  esac
done

for command in curl jq shasum tar; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required restore command not found: $command" >&2
    exit 1
  }
done

[[ ! -e "$runtime" ]] || {
  echo "Wine runtime destination already exists: $runtime" >&2
  exit 1
}

[[ -n "$repository" ]] || repository="$(jq -er '.repository | strings' "$artifact_lock")"
release_tag="$(jq -er '.releaseTag | strings' "$artifact_lock")"
asset_name="$(jq -er '.asset | strings' "$artifact_lock")"
expected_size="$(jq -er '.sizeBytes | numbers' "$artifact_lock")"
expected_sha256="$(jq -er '.sha256 | strings' "$artifact_lock")"
download_url="https://github.com/$repository/releases/download/$release_tag/$asset_name"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/rosilicon-runtime-restore.XXXXXX")"
archive="$work_dir/$asset_name"

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

echo "Downloading Wine runtime $release_tag from $repository ..."
curl -fL --retry 3 --retry-all-errors --progress-bar -o "$archive" "$download_url"

actual_size="$(wc -c < "$archive" | tr -d ' ')"
[[ "$actual_size" == "$expected_size" ]] || {
  echo "Wine runtime size mismatch: expected $expected_size, got $actual_size" >&2
  exit 1
}

actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
[[ "$actual_sha256" == "$expected_sha256" ]] || {
  echo "Wine runtime checksum mismatch: expected $expected_sha256, got $actual_sha256" >&2
  exit 1
}

archive_root="$(tar -tJf "$archive" | sed -n '1p')"
[[ "$archive_root" == ".wine-runtime/" ]] || {
  echo "Unexpected Wine runtime archive root: $archive_root" >&2
  exit 1
}

mkdir -p "$runtime"
tar -xJf "$archive" --strip-components 1 -C "$runtime"
if (( validate )); then
  "$script_dir/validate.sh" --runtime "$runtime"
fi

echo "Restored Wine runtime $release_tag at $runtime"
