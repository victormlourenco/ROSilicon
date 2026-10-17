#!/usr/bin/env bash
# Build the Vulkan driver and loader the Wine runtime ships: Mesa's KosmicKrisp
# and the Khronos loader in front of it, both x86_64.
#
# Wine's host side runs as x86_64 under Rosetta 2, so everything it dlopen()s
# has to be x86_64 too, and LunarG's KosmicKrisp is arm64 only. It is built
# here from the Mesa release Packaging/KosmicKrisp/source-lock.json pins, with
# the patches it lists for Mesa applied in order, in two passes:
#
#   1. mesa_clc and vtn_bindgen2, native arm64: build-time compilers that need
#      LLVM, SPIRV-LLVM-Translator and libclc, which Homebrew only has as arm64.
#   2. the driver itself, as a native x86_64 build under Rosetta — not a meson
#      cross build, which cannot link kk_clc, a build-time tool, against the
#      host's msl_compiler. Meson has to believe it runs on x86_64 for that, so
#      it runs from an x86_64 Python that uv fetches into the work folder.
#
# Unlike MoltenVK, a Mesa driver exports no vk* entry points of its own, only
# the ICD interface, so the Khronos loader is built beside it: it is what Wine
# loads as libvulkan.1.dylib, and VK_DRIVER_FILES tells it which driver to use.
#
#     build.sh                 build into .kosmickrisp
#     build.sh --output PATH   write the two dylibs to PATH instead
#     build.sh --work PATH     keep the checkouts and builds there (default a
#                              temporary folder, removed afterwards)
#     build.sh --install       install the toolchain with Homebrew first
#
# The output is what `make runtime` takes the two dylibs from the first time,
# before a published runtime carries them; see docs/kosmickrisp.md.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LOCK="$ROOT/Packaging/KosmicKrisp/source-lock.json"

OUTPUT="$ROOT/.kosmickrisp"
WORK=""
INSTALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            [[ $# -ge 2 ]] || { echo "error: --output needs a path" >&2; exit 1; }
            OUTPUT="$2"; shift 2 ;;
        --work)
            [[ $# -ge 2 ]] || { echo "error: --work needs a path" >&2; exit 1; }
            WORK="$2"; shift 2 ;;
        --install) INSTALL=1; shift ;;
        *) echo "usage: $(basename "$0") [--output PATH] [--work PATH] [--install]" >&2; exit 1 ;;
    esac
done

# Separate from the build, the same way d9vk-toolchain is, so a build reports a
# missing toolchain rather than installing one behind your back.
if [[ "$INSTALL" == 1 ]]; then
    brew install meson ninja cmake uv bison llvm spirv-llvm-translator libclc
fi

[[ "$(uname -m)" == "arm64" ]] || {
    echo "error: KosmicKrisp is built on Apple Silicon, under Rosetta 2" >&2
    exit 1
}
arch -x86_64 /usr/bin/true 2>/dev/null || {
    echo "error: Rosetta 2 is required: softwareupdate --install-rosetta --agree-to-license" >&2
    exit 1
}

BREW="${HOMEBREW_PREFIX:-/opt/homebrew}"
LLVM="$BREW/opt/llvm"

missing=()
for tool in git meson ninja cmake uv python3; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
for tool in "$BREW/opt/bison/bin/bison" "$LLVM/bin/llvm-config"; do
    [[ -x "$tool" ]] || missing+=("$tool")
done
[[ -d "$BREW/opt/spirv-llvm-translator" ]] || missing+=(spirv-llvm-translator)
[[ -d "$BREW/opt/libclc" ]] || missing+=(libclc)
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "error: not found: ${missing[*]}" >&2
    echo "       run 'make kosmickrisp-toolchain' to install them" >&2
    exit 1
fi

[[ -f "$LOCK" ]] || { echo "error: no source lock at $LOCK" >&2; exit 1; }

lock() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]][sys.argv[3]])' "$LOCK" "$1" "$2"; }

# An if, not a &&: the trap runs last, so its status becomes the script's, and
# a && that falls through reports 1 out of a build that succeeded.
TEMP=""
cleanup() { if [[ -n "$TEMP" ]]; then rm -rf "$TEMP"; fi; }
trap cleanup EXIT
if [[ -z "$WORK" ]]; then
    TEMP="$(mktemp -d)"
    WORK="$TEMP"
fi
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"

# What the lock calls the source: a tag for the loader and the headers, a
# branch for Mesa. Only for the line on screen — the commit is what is fetched.
ref() { python3 -c '
import json, sys
source = json.load(open(sys.argv[1]))[sys.argv[2]]
print(source.get("tag") or source.get("branch") or "?")
' "$LOCK" "$1"; }

# A checkout already at the locked commit is kept, so a --work folder makes a
# second build incremental.
#
# The commit is fetched by name rather than the ref it sits on: Mesa is pinned
# to a commit of `main`, whose tip moves on, and asking for the branch would
# get whatever landed since. Both hosts serve a commit this way, so there is
# one path for the branch and the tags alike, and it is the commit itself that
# arrives rather than something checked against it afterwards.
fetch() {
    local name="$1" dest="$WORK/$1"
    local repo commit
    repo="$(lock "$name" repository)"; commit="$(lock "$name" commit)"
    if [[ "$(git -C "$dest" rev-parse HEAD 2>/dev/null)" != "$commit" ]]; then
        echo "==> fetching $repo ($(ref "$name") $commit)"
        rm -rf "$dest"
        mkdir -p "$dest"
        git -C "$dest" init --quiet
        git -C "$dest" remote add origin "$repo"
        git -C "$dest" fetch --quiet --depth 1 origin "$commit"
        git -c advice.detachedHead=false -C "$dest" checkout --quiet FETCH_HEAD
    fi
}

fetch mesa
fetch loader
fetch headers

# Mesa's patches, relative to the lock. Put back to the locked commit first, so
# a checkout kept in --work is patched exactly once; only the files the patches
# touch change, so an incremental build stays incremental.
git -C "$WORK/mesa" checkout --quiet -- .
while IFS= read -r patch; do
    [[ -n "$patch" ]] || continue
    [[ -f "$patch" ]] || { echo "error: no patch at $patch" >&2; exit 1; }
    echo "==> applying $(basename "$patch")"
    git -C "$WORK/mesa" apply "$patch"
done < <(python3 -c '
import json, os, sys
lock = json.load(open(sys.argv[1]))
for patch in lock["mesa"].get("patches", []):
    print(os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), patch))
' "$LOCK")

SDK="$(xcrun --sdk macosx --show-sdk-path)"
CLANG="$(xcrun --sdk macosx --find clang)"
CLANGXX="$(xcrun --sdk macosx --find clang++)"

# ---- pass 1: mesa_clc, native -------------------------------------------------
CLC="$WORK/mesa-clc"
if [[ ! -x "$CLC/bin/mesa_clc" ]]; then
    echo "==> building mesa_clc (arm64)"
    rm -rf "$WORK/mesa-clc-build"
    (
        export PATH="$LLVM/bin:$BREW/opt/bison/bin:$PATH"
        export PKG_CONFIG_PATH="$LLVM/lib/pkgconfig:$BREW/lib/pkgconfig:$BREW/share/pkgconfig"
        log="$(meson setup "$WORK/mesa-clc-build" "$WORK/mesa" \
            --buildtype release --prefix "$CLC" \
            -Dgallium-drivers= -Dvulkan-drivers= -Dplatforms= -Dopengl=false \
            -Dglx=disabled -Degl=disabled -Dgles1=disabled -Dgles2=disabled \
            -Dllvm=enabled -Dshared-llvm=enabled \
            -Dmesa-clc=enabled -Dinstall-mesa-clc=true \
            -Dmesa-clc-bundle-headers=enabled 2>&1)" \
            || { echo "$log" >&2; exit 1; }
        ninja -C "$WORK/mesa-clc-build" install >/dev/null
    )
fi

# ---- pass 2: KosmicKrisp, x86_64 ---------------------------------------------
PY="$WORK/python-x86_64"
if [[ ! -x "$PY/bin/meson" ]]; then
    echo "==> fetching an x86_64 Python for meson"
    UV_PYTHON_INSTALL_DIR="$WORK/pythons" \
        uv venv --quiet --python cpython-3.12-macos-x86_64-none "$PY"
    uv pip install --quiet --python "$PY/bin/python" \
        meson==1.12.1 mako==1.4.3 pyyaml==6.0.3 packaging==26.3
fi

MIN=26.0   # KosmicKrisp only drives a Metal 4 GPU, so nothing older runs it.
cat > "$WORK/x86_64.ini" <<EOF
[binaries]
c = ['$CLANG', '-arch', 'x86_64', '-isysroot', '$SDK', '-mmacosx-version-min=$MIN']
cpp = ['$CLANGXX', '-arch', 'x86_64', '-isysroot', '$SDK', '-mmacosx-version-min=$MIN']
objc = ['$CLANG', '-arch', 'x86_64', '-isysroot', '$SDK', '-mmacosx-version-min=$MIN']
objcpp = ['$CLANGXX', '-arch', 'x86_64', '-isysroot', '$SDK', '-mmacosx-version-min=$MIN']
# Homebrew's libraries are arm64, so nothing is taken from pkg-config: the
# driver links only macOS's own zlib, expat and frameworks.
pkg-config = '/usr/bin/false'
EOF

KK="$WORK/mesa-kk-x86_64"
echo "==> building KosmicKrisp (x86_64)"
if [[ ! -d "$KK" ]]; then
    log="$(arch -x86_64 /usr/bin/env \
        PATH="$PY/bin:$CLC/bin:$BREW/opt/bison/bin:$BREW/bin:/usr/bin:/bin" \
        meson setup "$KK" "$WORK/mesa" --native-file "$WORK/x86_64.ini" \
            --buildtype release -Db_ndebug=true --prefix / \
            -Dgallium-drivers= -Dvulkan-drivers=kosmickrisp -Dplatforms=macos \
            -Dopengl=false -Dglx=disabled -Degl=disabled -Dgles1=disabled -Dgles2=disabled \
            -Dllvm=disabled -Dmesa-clc=system \
            -Dzstd=disabled -Dvalgrind=disabled -Dlibunwind=disabled 2>&1)" \
        || { echo "$log" >&2; exit 1; }
fi
arch -x86_64 /usr/bin/env \
    PATH="$PY/bin:$CLC/bin:$BREW/opt/bison/bin:$BREW/bin:/usr/bin:/bin" \
    ninja -C "$KK" src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib

# ---- the loader, x86_64 -------------------------------------------------------
echo "==> building the Vulkan loader (x86_64)"
cmake -S "$WORK/headers" -B "$WORK/headers-build" -DCMAKE_INSTALL_PREFIX="$WORK/headers-install" >/dev/null
cmake --install "$WORK/headers-build" >/dev/null
# Same deployment target as Wine, since the loader also fronts MoltenVK on a
# Mac too old for KosmicKrisp. The processor is named outright: the loader
# picks its assembly trampolines for unknown extension functions by it, and
# CMake would otherwise say arm64 and leave them out.
cmake -S "$WORK/loader" -B "$WORK/loader-build" -G Ninja \
    -DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR=x86_64 \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DCMAKE_OSX_SYSROOT="$SDK" \
    -DVULKAN_HEADERS_INSTALL_DIR="$WORK/headers-install" \
    -DBUILD_TESTS=OFF >/dev/null
ninja -C "$WORK/loader-build" >/dev/null

mkdir -p "$OUTPUT"
# The loader's versioned name is a symlink chain; the runtime gets one real
# file under the name Wine asks for.
cp -L "$WORK/loader-build/loader/libvulkan.1.dylib" "$OUTPUT/libvulkan.1.dylib"
cp "$KK/src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib" "$OUTPUT/"
for dylib in "$OUTPUT/libvulkan.1.dylib" "$OUTPUT/libvulkan_kosmickrisp.dylib"; do
    strip -x "$dylib"
done

echo "==> $OUTPUT"
shasum -a 256 "$OUTPUT"/*.dylib
