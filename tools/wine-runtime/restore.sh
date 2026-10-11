#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: restore.sh [--runtime PATH] [--repository OWNER/REPO] [--no-validate]

Fetches the runtime artifact-lock.json pins from the GitHub releases of the
repository it names, and checks it against the lock.

A published artifact older than runtime-lock.json is restored as the base of
the next build rather than as a runtime to ship, since its embedded lock
predates this checkout's; validate.sh is skipped in that case and says so.
--no-validate skips it whatever the revisions say.
EOF
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
artifact_lock="$repo_root/Packaging/WineRuntime/artifact-lock.json"
runtime_lock="$repo_root/Packaging/WineRuntime/runtime-lock.json"
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

# Never restored over: a tree already there may be one built rather than
# downloaded, and `make release-runtime` has not necessarily published it yet.
[[ ! -e "$runtime" ]] || {
  echo "Wine runtime destination already exists: $runtime" >&2
  echo "Remove it to restore a fresh one — 'rm -rf $runtime' — bearing in mind" >&2
  echo "that a tree built by 'make runtime' and not yet released cannot be" >&2
  echo "fetched back." >&2
  exit 1
}

[[ -n "$repository" ]] || repository="$(jq -er '.repository | strings' "$artifact_lock")"
release_tag="$(jq -er '.releaseTag | strings' "$artifact_lock")"
asset_name="$(jq -er '.asset | strings' "$artifact_lock")"
expected_size="$(jq -er '.sizeBytes | numbers' "$artifact_lock")"
expected_sha256="$(jq -er '.sha256 | strings' "$artifact_lock")"
download_url="https://github.com/$repository/releases/download/$release_tag/$asset_name"

# Which revision is published, against which one this checkout asks for. They
# part company whenever a runtime has been locked here but not released yet,
# which is the ordinary state of a branch that is building one — r18 published
# while runtime-lock.json already names r19, say.
#
# A tree restored in that state can only be the base `make runtime` builds the
# new revision on; it is not the runtime this checkout ships, and validate.sh
# compares the embedded lock against runtime-lock.json byte for byte, so
# checking it is a check that cannot pass. It used to be run anyway, which made
# `make restore` fail after the whole download on a mismatch both locks could
# have predicted beforehand. So the gap is read here, named, and the check left
# out — the restore itself is exactly as useful as it ever was.
artifact_revision="$(jq -er '.runtimeRevision | numbers' "$artifact_lock")"
checkout_revision="$(jq -er '.runtimeRevision | numbers' "$runtime_lock")"
base_only=0
if (( artifact_revision < checkout_revision )); then
  base_only=1
  if (( validate )); then
    validate=0
    echo "This checkout's runtime-lock.json names r$checkout_revision, and the" >&2
    echo "published artifact is r$artifact_revision — r$checkout_revision has not been released." >&2
    echo "Restoring r$artifact_revision as the base to build it on; not checking it against" >&2
    echo "the lock, which only r$checkout_revision can match." >&2
  fi
elif (( artifact_revision > checkout_revision )); then
  # The other direction is not a gap to work around but a mistake: nothing
  # bumps artifact-lock.json except releasing a runtime this checkout locked,
  # so an artifact ahead of the lock means one of the two was not committed.
  echo "artifact-lock.json names r$artifact_revision, ahead of runtime-lock.json's r$checkout_revision." >&2
  echo "The locks disagree about which revision is current, so one of them is stale." >&2
  exit 1
fi
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

if (( base_only )); then
  echo "Restored Wine runtime $release_tag at $runtime, as the base for r$checkout_revision."
  echo "Run 'make runtime' to build r$checkout_revision on it; this tree is not one to ship."
else
  echo "Restored Wine runtime $release_tag at $runtime"
fi
