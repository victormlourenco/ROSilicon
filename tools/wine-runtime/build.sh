#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: build.sh --source PATH --build PATH --install PATH --libs PATH [--jobs COUNT]

Builds the pinned macOS Wine source as an x86_64 host with i386 and x86_64
Windows modules, on Apple Silicon under Rosetta 2. Homebrew no longer builds
Intel bottles, so the host side is compiled by Xcode's clang for x86_64, with
headers from the arm64 Homebrew at HOMEBREW_PREFIX (default /opt/homebrew).

--libs names a folder of x86_64 libfreetype.6, libgnutls.30 and libMoltenVK
dylibs, a runtime's lib/external: configure links its probes against them to
learn their names, and Wine dlopen()s them by those names at run time.
EOF
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
patch_root="$repo_root/Packaging/WineRuntime/patches"
source_root=""
build_root=""
install_root=""
libs_root=""
jobs=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || usage
      source_root="$2"
      shift 2
      ;;
    --build)
      [[ $# -ge 2 ]] || usage
      build_root="$2"
      shift 2
      ;;
    --install)
      [[ $# -ge 2 ]] || usage
      install_root="$2"
      shift 2
      ;;
    --libs)
      [[ $# -ge 2 ]] || usage
      libs_root="$2"
      shift 2
      ;;
    --jobs)
      [[ $# -ge 2 ]] || usage
      jobs="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$source_root" && -n "$build_root" && -n "$install_root" && -n "$libs_root" ]] || usage
[[ -z "$jobs" || "$jobs" =~ ^[1-9][0-9]*$ ]] || usage

[[ -x "$source_root/configure" ]] || {
  echo "Wine configure script not found: $source_root/configure" >&2
  exit 1
}

[[ ! -e "$build_root" ]] || {
  echo "Build path already exists: $build_root" >&2
  exit 1
}

[[ ! -e "$install_root" ]] || {
  echo "Install path already exists: $install_root" >&2
  exit 1
}

[[ "$(uname -m)" == "arm64" ]] || {
  echo "The runtime is built on Apple Silicon, under Rosetta 2." >&2
  exit 1
}

arch -x86_64 /usr/bin/true 2>/dev/null || {
  echo "Rosetta 2 is required: softwareupdate --install-rosetta --agree-to-license" >&2
  exit 1
}

libs_root="$(cd "$libs_root" && pwd)"
for library in libfreetype.6.dylib libgnutls.30.dylib libMoltenVK.dylib; do
  file "$libs_root/$library" 2>/dev/null | grep -q 'x86_64' || {
    echo "No x86_64 $library in $libs_root" >&2
    exit 1
  }
done

brew_prefix="${HOMEBREW_PREFIX:-/opt/homebrew}"
export PATH="$brew_prefix/opt/bison/bin:$brew_prefix/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PKG_CONFIG_PATH="$brew_prefix/lib/pkgconfig:$brew_prefix/share/pkgconfig"

# Xcode's own SDK, named outright: a Command Line Tools SDK newer than Xcode's
# linker would otherwise be picked up, and that linker cannot read it.
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
export CC="$(xcrun --sdk macosx --find clang) -arch x86_64"
export CXX="$(xcrun --sdk macosx --find clang++) -arch x86_64"

for command in bison flex git i686-w64-mingw32-gcc x86_64-w64-mingw32-gcc make pkg-config; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required build command not found: $command" >&2
    exit 1
  }
done

pkg-config --exists freetype2 gnutls || {
  echo "FreeType and GnuTLS headers are required under $brew_prefix" >&2
  exit 1
}

for patch in "$patch_root"/*.patch; do
  [[ -e "$patch" ]] || continue
  git -C "$source_root" apply --check "$patch"
  git -C "$source_root" apply "$patch"
done

if [[ -z "$jobs" ]]; then
  jobs="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"
fi

configure_options=(
  --build=x86_64-apple-darwin
  --prefix="$install_root"
  --enable-archs=i386,x86_64
  --disable-tests
  --without-alsa
  --without-capi
  --without-cups
  --without-dbus
  --without-ffmpeg
  --without-fontconfig
  --without-gettext
  --without-gphoto
  --with-gnutls
  --without-gssapi
  --without-gstreamer
  --without-hwloc
  --without-inotify
  --without-krb5
  --without-netapi
  --without-opencl
  --without-opengl
  --without-oss
  --without-pcap
  --without-pcsclite
  --without-pulse
  --without-sane
  --without-sdl
  --without-udev
  --without-usb
  --without-v4l2
  --without-wayland
  --without-x
)

# The Homebrew headers are arm64-neutral, but its libraries are arm64 only:
# the link flags are set here so pkg-config never adds its -L, and the -l
# names resolve against the x86_64 copies instead. Copies, not links: their
# ids are @loader_path/..., right for the runtime but not for the build tools
# that link FreeType and run mid-build (sfnt2fon). Ids naming where the copies
# lie let those tools load them; the modules Wine ships dlopen() them by leaf
# name, and configure reads only the leaf out of the id.
link_root="$build_root/x86_64-libs"
mkdir -p "$link_root"
cp -pX "$libs_root"/*.dylib "$link_root/"
for library in libfreetype.6.dylib libgnutls.30.dylib; do
  install_name_tool -id "$link_root/$library" "$link_root/$library" 2>/dev/null
  codesign --force --sign - "$link_root/$library"
done
ln -s libfreetype.6.dylib "$link_root/libfreetype.dylib"
ln -s libgnutls.30.dylib "$link_root/libgnutls.dylib"

configure_environment=(
  LDFLAGS="-L$link_root"
  FREETYPE_CFLAGS="$(pkg-config --cflags freetype2)"
  FREETYPE_LIBS="-lfreetype"
  GNUTLS_CFLAGS="$(pkg-config --cflags gnutls)"
  GNUTLS_LIBS="-lgnutls"
  # There is no x86_64 Vulkan loader to probe. The runtime links this name
  # to MoltenVK in lib/wine/x86_64-unix; see assemble.sh.
  ac_cv_lib_soname_vulkan="libvulkan.1.dylib"
)

(
  cd "$build_root"
  arch -x86_64 /usr/bin/env "${configure_environment[@]}" \
    /bin/sh "$source_root/configure" "${configure_options[@]}"
)

arch -x86_64 /usr/bin/make -C "$build_root" -j "$jobs"

preserve_root="$(mktemp -d "${TMPDIR:-/tmp}/rosilicon-wine-preserve.XXXXXX")"
cleanup_preserved_binaries() {
  rm -rf "$preserve_root"
}
trap cleanup_preserved_binaries EXIT

cp "$build_root/tools/wine/wine" "$preserve_root/wine-wrapper"
cp "$build_root/loader/wine" "$preserve_root/wine-loader"
cp "$build_root/dlls/ntdll/ntdll.so" "$preserve_root/ntdll.so"

arch -x86_64 /usr/bin/make -C "$build_root" install-lib INSTALL_PROGRAM_FLAGS=--strip
install -m 755 "$preserve_root/wine-wrapper" "$install_root/bin/wine"
install -m 755 "$preserve_root/wine-loader" "$install_root/lib/wine/x86_64-unix/wine"
install -m 755 "$preserve_root/ntdll.so" "$install_root/lib/wine/x86_64-unix/ntdll.so"

cleanup_preserved_binaries
trap - EXIT

[[ -x "$install_root/bin/wine" && -x "$install_root/bin/wineserver" ]] || {
  echo "Wine installation did not produce the expected executables." >&2
  exit 1
}

file "$install_root/bin/wine" | grep -q 'x86_64' || {
  echo "Installed Wine loader is not x86_64." >&2
  exit 1
}

echo "Built Wine runtime into $install_root"
