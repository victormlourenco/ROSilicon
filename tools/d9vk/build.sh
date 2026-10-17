#!/usr/bin/env bash
# Build the d3d9.dll the app ships, from the pinned DXVK with our patches on top.
#
# The client is a 32-bit Windows program, so DXVK has to come out as a 32-bit PE
# and needs the mingw-w64 cross-compiler rather than the system clang, plus
# meson, ninja and glslang. The source is not vendored:
# Packaging/D9VK/source-lock.json names the repository, branch and commit, and
# the patches it lists, relative to it, are applied to that commit in order.
#
# There are two locks, one per Vulkan driver: that one, the patched
# moltenvk-version branch MoltenVK needs, and Packaging/D9VK/kosmickrisp/
# source-lock.json, K0bin's master for KosmicKrisp.
#
#     build.sh                 build into .d9vk
#     build.sh --lock PATH     build from another source lock
#     build.sh --output PATH   write the .dll to PATH instead
#     build.sh --src PATH      reuse an existing checkout instead of cloning
#     build.sh --install       install the toolchain with Homebrew first
#
# The .dll lands in .d9vk, which is gitignored, and build.sh copies it into the
# app from there in preference to the checked-in Resources/d9vk/d3d9.dll. This
# is the slow one of the two build products — a clone of DXVK and a few minutes
# of compiling — so nothing runs it behind your back: `make d9vk` and
# `make bundle` do, an ordinary `make` does not.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LOCK="$ROOT/Packaging/D9VK/source-lock.json"

OUTPUT="$ROOT/.d9vk/d3d9.dll"
SRC=""
INSTALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lock)
            [[ $# -ge 2 ]] || { echo "error: --lock needs a path" >&2; exit 1; }
            LOCK="$2"; shift 2 ;;
        --output)
            [[ $# -ge 2 ]] || { echo "error: --output needs a path" >&2; exit 1; }
            OUTPUT="$2"; shift 2 ;;
        --src)
            [[ $# -ge 2 ]] || { echo "error: --src needs a path" >&2; exit 1; }
            SRC="$2"; shift 2 ;;
        --install) INSTALL=1; shift ;;
        *) echo "usage: $(basename "$0") [--lock PATH] [--output PATH] [--src PATH] [--install]" >&2; exit 1 ;;
    esac
done

# Separate from the build, the same way steam-stub-toolchain is, so a build
# reports a missing toolchain rather than installing one behind your back.
if [[ "$INSTALL" == 1 ]]; then
    brew install mingw-w64 meson ninja glslang
fi

missing=()
for tool in git meson ninja glslangValidator i686-w64-mingw32-g++ python3; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "error: not found: ${missing[*]}" >&2
    echo "       run 'make d9vk-toolchain' to install the cross-compiler" >&2
    exit 1
fi

[[ -f "$LOCK" ]] || { echo "error: no source lock at $LOCK" >&2; exit 1; }

read -r REPO BRANCH COMMIT < <(python3 -c '
import json, sys
lock = json.load(open(sys.argv[1]))
print(lock["repository"], lock["branch"], lock["commit"])
' "$LOCK")
# One per line, resolved against the lock's own folder. An empty list is a
# build of the commit as it is.
PATCHES=()
while IFS= read -r patch; do
    [[ -n "$patch" ]] && PATCHES+=("$patch")
done < <(python3 -c '
import json, os, sys
lock = json.load(open(sys.argv[1]))
for patch in lock.get("patches", []):
    print(os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), patch))
' "$LOCK")

CLONED=""
# An if, not a &&: the trap runs last, so its status becomes the script's, and
# a && that falls through reports 1 out of a build that succeeded.
cleanup() { if [[ -n "$CLONED" ]]; then rm -rf "$CLONED"; fi; }
trap cleanup EXIT

# A checkout passed with --src is used as it is: it is assumed to be at the
# locked commit with the patches already applied, which is what you want while
# iterating on them.
if [[ -n "$SRC" ]]; then
    echo "==> using $SRC"
else
    CLONED="$(mktemp -d)"
    SRC="$CLONED/dxvk"
    echo "==> cloning $REPO ($BRANCH)"
    git clone --quiet --branch "$BRANCH" --single-branch "$REPO" "$SRC"
    git -C "$SRC" checkout --quiet "$COMMIT"
    git -C "$SRC" submodule update --quiet --init --recursive --depth 1

    # In the lock's order, which is the order they are numbered.
    for patch in ${PATCHES[@]+"${PATCHES[@]}"}; do
        [[ -f "$patch" ]] || { echo "error: no patch at $patch" >&2; exit 1; }
        echo "==> applying $(basename "$patch")"
        git -C "$SRC" apply "$patch"
    done
fi

echo "==> building (release, 32-bit)"
BUILD="$SRC/build32"
# Both directories are named, because meson takes the source from the working
# directory otherwise and this does not run from inside the checkout. Its
# chatter is only worth seeing when it fails, and it reports on stdout.
if [[ ! -d "$BUILD" ]]; then
    log="$(meson setup --cross-file "$SRC/build-win32.txt" \
        --buildtype release "$BUILD" "$SRC" 2>&1)" \
        || { echo "$log" >&2; exit 1; }
fi
ninja -C "$BUILD" src/d3d9/d3d9.dll

mkdir -p "$(dirname "$OUTPUT")"
cp "$BUILD/src/d3d9/d3d9.dll" "$OUTPUT"
# Unstripped it is around 15 MB of debug data the app has no use for.
i686-w64-mingw32-strip "$OUTPUT"

echo "==> $OUTPUT"
