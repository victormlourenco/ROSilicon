#!/usr/bin/env bash
# Stage a built d9mt into .d9mt, in the layout build.sh copies into the app.
#
# Unlike DXVK, d9mt is not built here. Building it takes a checkout of
# https://github.com/neo773/d9mt-v2, its own five scripts in order, an LLVM 15
# built as x86_64 static libs, and a clone of upstream DXVK 3.0 that its
# fetch-deps.sh vendors — and every one of those scripts links against
# CrossOver's wine tree rather than ours. So this script takes a checkout
# somebody has already built and copies the seven products out of it:
#
#     stage.sh --src PATH          stage from that d9mt-v2 checkout
#     stage.sh --output PATH       stage somewhere other than .d9mt
#     stage.sh --lock PATH         read another source lock
#     stage.sh --any-commit        stage a checkout that is not at the locked one
#
# Packaging/D9MT/source-lock.json names the commit a staged build has to come
# from and where each product lies inside the checkout. The commit is checked
# because none of this is reproducible on its own: the tree carries no version
# string, so a staged d3d9.dll says nothing about which d9mt it is, and the
# lock is the only record.
#
# What lands in .d9mt:
#
#     d3d9.dll                           the whole D3D9 implementation, i686 PE
#     wine/i386-windows/winemetal.dll    the bridge to Metal, PE side
#     wine/i386-windows/d9mtair.dll      its shader compiler, PE side
#     wine/x86_64-windows/…              the same two, for 64-bit programs
#     wine/x86_64-unix/winemetal.so      the bridge's unix side, where Metal is
#     wine/x86_64-unix/d9mtair.so        the compiler's, LLVM and all
#     staged-lock.json                   the lock this was staged against
#
# wine/ mirrors the runtime's lib/wine/, so build.sh overlays it onto the
# bundled Wine tree with a plain copy. The builtins have to go in there, before
# the bundle is signed: nothing writes to that tree afterwards.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LOCK="$ROOT/Packaging/D9MT/source-lock.json"

OUTPUT="$ROOT/.d9mt"
SRC=""
ANY_COMMIT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src)
            [[ $# -ge 2 ]] || { echo "error: --src needs a path" >&2; exit 1; }
            SRC="$2"; shift 2 ;;
        --output)
            [[ $# -ge 2 ]] || { echo "error: --output needs a path" >&2; exit 1; }
            OUTPUT="$2"; shift 2 ;;
        --lock)
            [[ $# -ge 2 ]] || { echo "error: --lock needs a path" >&2; exit 1; }
            LOCK="$2"; shift 2 ;;
        --any-commit)
            ANY_COMMIT=1; shift ;;
        *)
            echo "usage: $(basename "$0") --src PATH [--output PATH] [--lock PATH] [--any-commit]" >&2
            exit 2 ;;
    esac
done

[[ -f "$LOCK" ]] || { echo "error: no source lock at $LOCK" >&2; exit 1; }

if [[ -z "$SRC" ]]; then
    echo "error: --src must name a built d9mt-v2 checkout" >&2
    echo "       see docs/d9mt.md for how one is built" >&2
    exit 1
fi
SRC="$(cd "$SRC" 2>/dev/null && pwd)" || {
    echo "error: no such folder: $SRC" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 1; }

read -r REPO COMMIT < <(python3 -c '
import json, sys
lock = json.load(open(sys.argv[1]))
print(lock["repository"], lock["commit"])
' "$LOCK")

# The lock says which commit, and a staged build carries no version of its own,
# so this is the only moment the two can be compared. --any-commit is for
# working on d9mt itself; a release is staged from the locked commit.
if [[ "$ANY_COMMIT" == 0 ]]; then
    [[ -d "$SRC/.git" ]] || {
        echo "error: $SRC is not a git checkout, so its commit cannot be checked" >&2
        echo "       pass --any-commit to stage it anyway" >&2
        exit 1
    }
    head="$(git -C "$SRC" rev-parse HEAD)"
    if [[ "$head" != "$COMMIT" ]]; then
        echo "error: $SRC is at $head" >&2
        echo "       the lock names  $COMMIT" >&2
        echo "       check that commit out and rebuild, or pass --any-commit" >&2
        exit 1
    fi
    if [[ -n "$(git -C "$SRC" status --porcelain -- ':!build' 2>/dev/null)" ]]; then
        echo "warning: $SRC has uncommitted changes outside build/" >&2
    fi
fi

# path-in-.d9mt <TAB> path-in-checkout, straight out of the lock.
PRODUCTS=()
while IFS= read -r line; do
    [[ -n "$line" ]] && PRODUCTS+=("$line")
done < <(python3 -c '
import json, sys
lock = json.load(open(sys.argv[1]))
for destination, source in lock["products"].items():
    print(destination + "\t" + source)
' "$LOCK")

if [[ ${#PRODUCTS[@]} -eq 0 ]]; then
    echo "error: the lock lists no products" >&2
    exit 1
fi

missing=()
for entry in "${PRODUCTS[@]}"; do
    source="$SRC/${entry#*$'\t'}"
    [[ -f "$source" ]] || missing+=("${entry#*$'\t'}")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "error: $SRC has not been built — missing:" >&2
    printf '       %s\n' "${missing[@]}" >&2
    echo "       see docs/d9mt.md for the five scripts, in order" >&2
    exit 1
fi

# Replaced rather than merged: a leftover from an older staging would ship, and
# nothing downstream would say which build it came from.
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"
echo "==> staging d9mt from $SRC"
for entry in "${PRODUCTS[@]}"; do
    destination="${entry%%$'\t'*}"
    source="${entry#*$'\t'}"
    mkdir -p "$OUTPUT/$(dirname "$destination")"
    cp "$SRC/$source" "$OUTPUT/$destination"
    echo "    $destination <- $source"
done

# The lock travels with what was staged against it, so validate.sh and anyone
# reading .d9mt later can say which d9mt this is.
cp "$LOCK" "$OUTPUT/staged-lock.json"
echo "    staged-lock.json <- ${LOCK#$ROOT/}"
echo "    $REPO @ ${COMMIT:0:12}"
echo "==> staged into $OUTPUT"
