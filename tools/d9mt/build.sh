#!/usr/bin/env bash
# Build d9mt — Direct3D 9 straight onto Metal — and stage it into .d9mt.
#
#     build.sh                 build into .d9mt
#     build.sh --output PATH   stage somewhere else
#     build.sh --work PATH     keep the checkouts and LLVM somewhere else
#
# The work folder defaults to .d9mt-build and deliberately sits outside
# .build: that one is SwiftPM's and is what `make clean` removes, and an hour
# of LLVM does not belong anywhere a clean can reach. Worse than losing it is
# racing it — a `make clean` while this is running deletes the pack git is
# writing and the clone fails with "invalid index-pack output", which looks
# like a network fault and is not one.
#     build.sh --lock PATH     read another source lock
#     build.sh --install       install the toolchain with Homebrew first
#     build.sh --toolchain     install the toolchain and stop
#     build.sh --keep-going    carry on to staging even if a step fails
#
# --toolchain exists where tools/d9vk has no equivalent — `make d9vk-toolchain`
# installs and then builds, which is fine for a few minutes and not for this.
#
# This is the longest build in the repository by a wide margin: four
# repositories cloned and an LLVM built from source, most of an hour the first
# time. Everything is cached in the work folder, so a second run is only the
# three d9mt scripts, a couple of minutes.
#
# ---------------------------------------------------------------------------
# Why there is a script here at all
#
# d9mt builds with its own five scripts, and they resolve `$ROOT` as the
# parent of the checkout: v2 was extracted out of d9mt v1 and kept the
# references. So a bare `git clone` of d9mt-v2 cannot build — it needs v1
# around it for tools/make-builtin.py and vendor/spirv-cross, a dxmt checkout
# beside that for the airconv headers, and a DXVK clone inside it that none of
# its scripts creates but build-driver.sh's link reads d3d9.def from. Getting
# that layout right by hand is the whole difficulty, and getting it subtly
# wrong is worse than failing: make-builtin.py sits behind an `if [ -f ]`, so a
# v2 checkout in the wrong place builds, stages, ships, and then the builtins
# do not load.
#
# So the layout is what this script mostly is:
#
#     <work>/d9mt/                          v1 — $ROOT: tools/, vendor/, prebuilt/
#     <work>/d9mt/d9mt-v2/                  the d9mt-v2 checkout, at the locked commit
#     <work>/d9mt/d9mt-v2/DXVK-3.0-uptsream the extraction source (upstream's spelling)
#     <work>/d9mt/d9mt-v2/toolchains/       the x86_64 LLVM, built once and kept
#     <work>/dxmt/                          for -I src/airconv
#
# Beside v1 but NOT at <work>/d9mt/v2: v1 carries a tracked v2/ of its own, an
# older in-repo version of the same thing — the one the stale scripts/build.sh
# still targets — and the standalone repository is what replaced it. Only the
# checkout's *parent* matters to its scripts ($V2 is wherever they live, $ROOT
# is one above), so the folder is named after the repository and v1's own v2/
# is left alone.
#
# Each of the four is pinned by commit in the source lock, the DXVK clone
# included — fetch-deps.sh would otherwise clone whatever main was that day,
# which made two stagings of one d9mt commit different drivers.
#
# What this does NOT fix is in docs/d9mt.md: no license upstream, and a bridge
# whose unixlib ABI is CrossOver's rather than our Wine's.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
LOCK="$REPO_ROOT/Packaging/D9MT/source-lock.json"

OUTPUT="$REPO_ROOT/.d9mt"
WORK="$REPO_ROOT/.d9mt-build"
INSTALL=0
TOOLCHAIN_ONLY=0
KEEP_GOING=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            [[ $# -ge 2 ]] || { echo "error: --output needs a path" >&2; exit 1; }
            OUTPUT="$2"; shift 2 ;;
        --work)
            [[ $# -ge 2 ]] || { echo "error: --work needs a path" >&2; exit 1; }
            WORK="$2"; shift 2 ;;
        --lock)
            [[ $# -ge 2 ]] || { echo "error: --lock needs a path" >&2; exit 1; }
            LOCK="$2"; shift 2 ;;
        --install) INSTALL=1; shift ;;
        --toolchain) INSTALL=1; TOOLCHAIN_ONLY=1; shift ;;
        --keep-going) KEEP_GOING=1; shift ;;
        *)
            echo "usage: $(basename "$0") [--output PATH] [--work PATH] [--lock PATH]" >&2
            echo "       [--install] [--toolchain] [--keep-going]" >&2
            exit 2 ;;
    esac
done

# Separate from the build, the way d9vk-toolchain is, so a build reports a
# missing toolchain rather than installing one behind your back.
#
# llvm@15 is the one that surprises: build-air-compiler.sh, which
# build-bridge.sh runs for its smoke test, needs a *host* llvm-config, and
# build-llvm-unixside.sh builds its x86_64 LLVM with LLVM_BUILD_TOOLS=Off and
# so produces none. Both LLVMs are required, for different sides.
if [[ "$INSTALL" == 1 ]]; then
    brew install mingw-w64 glslang spirv-cross cmake ninja llvm@15
    if [[ "$TOOLCHAIN_ONLY" == 1 ]]; then
        echo "==> toolchain installed; run 'make d9mt' to build"
        exit 0
    fi
fi

missing=()
for tool in git python3 cmake ninja glslangValidator spirv-cross \
            i686-w64-mingw32-g++ i686-w64-mingw32-gcc i686-w64-mingw32-dlltool \
            x86_64-w64-mingw32-gcc x86_64-w64-mingw32-dlltool; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
xcrun -sdk macosx -f metal >/dev/null 2>&1 || missing+=("xcrun metal (Xcode)")
# Not on PATH and not interchangeable with another version: the AIR compiler
# includes LLVM 15's headers, so llvm@23 in its place is a page of errors.
LLVM15_CONFIG="${LLVM_CONFIG:-/opt/homebrew/opt/llvm@15/bin/llvm-config}"
[[ -x "$LLVM15_CONFIG" ]] || missing+=("llvm@15 (brew, for $LLVM15_CONFIG)")
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "error: not found: ${missing[*]}" >&2
    echo "       run 'make d9mt-toolchain' to install them" >&2
    exit 1
fi

# build-bridge.sh refuses outright without this, and it cannot be installed
# from here — so it is said before an hour of building rather than after.
CROSSOVER="${CROSSOVER:-/Applications/CrossOver.app/Contents/SharedSupport/CrossOver}"
[[ -f "$CROSSOVER/lib/wine/x86_64-unix/ntdll.so" ]] || {
    echo "error: no CrossOver wine tree at $CROSSOVER/lib/wine/x86_64-unix" >&2
    echo "       build-bridge.sh links the unix side against its ntdll.so and" >&2
    echo "       refuses without it. See docs/d9mt.md." >&2
    exit 1
}

[[ -f "$LOCK" ]] || { echo "error: no source lock at $LOCK" >&2; exit 1; }

read -r V2_REPO V2_COMMIT ROOT_REPO ROOT_COMMIT DXMT_REPO DXMT_COMMIT \
        DXVK_REPO DXVK_COMMIT < <(python3 -c '
import json, sys
lock = json.load(open(sys.argv[1]))
sources = lock["sources"]
print(lock["repository"], lock["commit"],
      sources["root"]["repository"], sources["root"]["commit"],
      sources["dxmt"]["repository"], sources["dxmt"]["commit"],
      sources["dxvkReference"]["repository"], sources["dxvkReference"]["commit"])
' "$LOCK")

ROOT_DIR="$WORK/d9mt"
V2_DIR="$ROOT_DIR/d9mt-v2"
DXMT_DIR="$WORK/dxmt"
DXVK_DIR="$V2_DIR/DXVK-3.0-uptsream"

# Clones `repo` at exactly `commit`, or leaves a checkout already there alone.
#
# init + fetch --depth 1 <sha> rather than clone + checkout: the commits pinned
# here are not branch tips, and GitHub serves a shallow fetch of any reachable
# sha, so this takes one commit of each repository instead of the history.
pin_checkout() {
    local name="$1" dir="$2" repo="$3" commit="$4"
    if [[ -d "$dir/.git" ]]; then
        if [[ "$(git -C "$dir" rev-parse HEAD)" == "$commit" ]]; then
            echo "    $name: already at ${commit:0:12}"
            return
        fi
        echo "==> $name: fetching ${commit:0:12}"
        git -C "$dir" fetch --quiet --depth 1 origin "$commit"
    else
        [[ ! -e "$dir" ]] || {
            echo "error: $dir is in the way and is not a git checkout" >&2
            exit 1
        }
        echo "==> $name: cloning $repo at ${commit:0:12}"
        mkdir -p "$dir"
        git -C "$dir" init --quiet
        git -C "$dir" remote add origin "$repo"
        git -C "$dir" fetch --quiet --depth 1 origin "$commit"
    fi
    git -C "$dir" checkout --quiet --detach FETCH_HEAD
}

echo "==> work folder $WORK"
mkdir -p "$WORK"
# v1 first: it is the folder v2 goes inside, so the order is not a free choice.
pin_checkout "d9mt (v1, \$ROOT)" "$ROOT_DIR" "$ROOT_REPO" "$ROOT_COMMIT"
pin_checkout "d9mt-v2" "$V2_DIR" "$V2_REPO" "$V2_COMMIT"
pin_checkout "dxmt" "$DXMT_DIR" "$DXMT_REPO" "$DXMT_COMMIT"
pin_checkout "dxvk (extraction source)" "$DXVK_DIR" "$DXVK_REPO" "$DXVK_COMMIT"

# The submodules fetch-deps.sh vendors out of that clone. Named rather than
# recursive: the rest of DXVK's submodules are build-time tooling it has no use
# for here.
echo "==> dxvk submodules (dxbc-spirv, vulkan, spirv headers)"
git -C "$DXVK_DIR" submodule update --quiet --init --depth 1 \
    subprojects/dxbc-spirv include/vulkan include/spirv

# Each step says what it is before it runs, since the long ones look hung
# otherwise, and `step` is also where --keep-going is honoured.
failed=()
step() {
    local name="$1"; shift
    echo "==> $name"
    if "$@"; then
        return 0
    fi
    failed+=("$name")
    if [[ "$KEEP_GOING" == 1 ]]; then
        echo "warning: $name failed; carrying on (--keep-going)" >&2
        return 0
    fi
    echo "error: $name failed" >&2
    exit 1
}

# fetch-deps.sh takes the DXVK clone as its argument and skips cloning when the
# folder is already a checkout — which is how the pinned clone above gets used
# instead of a fresh one of main. It vendors the d3d9 frontend, util/spirv/wsi
# and dxbc-spirv into the v2 tree, all of it gitignored there.
step "vendoring the DXVK frontend" \
    bash "$V2_DIR/scripts/fetch-deps.sh" "$DXVK_DIR"

# The expensive one, and the reason the work folder is worth keeping: an LLVM
# 15 as x86_64 static libs, for the AIR emitter that runs on Wine's unix side.
# Skipped entirely once built — the script itself would re-run cmake.
if [[ -f "$V2_DIR/toolchains/llvm-x86_64/lib/libLLVMBitWriter.a" ]]; then
    echo "    LLVM: already built in $V2_DIR/toolchains/llvm-x86_64"
else
    echo "    LLVM 15 as x86_64 static libs — tens of minutes, around 3 GB"
    step "building LLVM" bash "$V2_DIR/scripts/build-llvm-unixside.sh"
fi

step "building the AIR emitter (d9mtair)" bash "$V2_DIR/scripts/build-d9mtair.sh"
step "building the bridge (winemetal)" bash "$V2_DIR/scripts/build-bridge.sh"
step "building the driver (d3d9.dll)" bash "$V2_DIR/scripts/build-driver.sh"

if [[ ${#failed[@]} -gt 0 ]]; then
    echo "warning: these steps failed and the staging below is incomplete:" >&2
    printf '         %s\n' "${failed[@]}" >&2
fi

# Staged through stage.sh rather than copied here, so there is one description
# of where the seven products come from and what the layout is. The commit
# check passes by construction: the checkout above is at the locked commit.
step "staging" "$HERE/stage.sh" --src "$V2_DIR" --output "$OUTPUT" --lock "$LOCK"
step "validating" "$HERE/validate.sh" --d9mt "$OUTPUT"

echo "==> d9mt staged in $OUTPUT"
echo "    the work folder is kept; a second build is minutes, not an hour"
[[ ${#failed[@]} -eq 0 ]] || exit 1
