# KosmicKrisp

DXVK turns the client's Direct3D 9 into Vulkan, and a Vulkan driver turns that
into Metal. On macOS 26 and later that driver is
[KosmicKrisp](https://docs.mesa3d.org/drivers/kosmickrisp.html), Mesa's
Vulkan-on-Metal driver. It is a conformant Vulkan 1.4 implementation where
MoltenVK is a portability subset. On an older Mac it is MoltenVK, as before:
KosmicKrisp only drives a GPU with Metal 4, which macOS offers from 26 on.

## How Wine reaches it

MoltenVK exports the whole Vulkan API itself, so the runtime used to link Wine's
`libvulkan.1.dylib` straight to it. A Mesa driver exports only the
driver-to-loader interface, so the runtime now carries the
[Khronos loader](https://github.com/KhronosGroup/Vulkan-Loader) as
`lib/external/libvulkan.1.dylib`, with both drivers beside it:

```
lib/wine/x86_64-unix/libvulkan.1.dylib -> ../../external/libvulkan.1.dylib
lib/external/libvulkan.1.dylib              the loader
lib/external/libvulkan_kosmickrisp.dylib
lib/external/libMoltenVK.dylib
share/vulkan/icd.d/kosmickrisp_icd.json     written by assemble.sh
share/vulkan/icd.d/moltenvk_icd.json
```

`Paths.wineEnvironment` sets `VK_DRIVER_FILES` to one of the two manifests for
every wine the launcher starts, so the loader never searches the system for
drivers and a Vulkan SDK installed on the Mac cannot add one.
`VulkanDriver.onThisMac` makes the choice. `RO_VULKAN_DRIVER=moltenvk` in the
launcher's environment picks MoltenVK on a Mac that runs both, which is useful
for comparing the two:

```sh
RO_VULKAN_DRIVER=moltenvk open ROSilicon.app
```

The game's log names the driver it got. `MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1`
is still set: MoltenVK needs it, and KosmicKrisp ignores it.

## Why it is built here

Wine's host side runs as x86_64 under Rosetta 2, so every library it loads has
to be x86_64. The KosmicKrisp in LunarG's Vulkan SDK is arm64 only, and
Homebrew's loader is arm64 only. `make kosmickrisp` builds both from the sources
[Packaging/KosmicKrisp/source-lock.json](../Packaging/KosmicKrisp/source-lock.json)
pins (a Mesa release, and the loader and headers of one Vulkan SDK) into
`.kosmickrisp`. It takes a few minutes, in three steps:

1. **`mesa_clc` and `vtn_bindgen2`, arm64.** Mesa compiles part of its driver
   from OpenCL C at build time. These tools need LLVM, SPIRV-LLVM-Translator and
   libclc, which Homebrew only has for arm64, and they never ship, so they are
   built natively.
2. **KosmicKrisp, x86_64.** This is a *native* x86_64 build under Rosetta, not
   a meson cross build. KosmicKrisp's build-time `kk_clc` links the same MSL
   compiler library the driver does, and meson will not link a build-machine
   tool against a host-machine library. For meson to treat x86_64 as native, it
   has to run from an x86_64 Python, which uv fetches into the work folder. The
   driver links only macOS's own zlib, expat and frameworks.
3. **The loader, x86_64**, with CMake told the processor outright. Otherwise it
   takes the arm64 host for the target and leaves out the assembly trampolines
   it uses for extension functions it does not know.

`make kosmickrisp-toolchain` installs what it needs with Homebrew.

## Getting it into the runtime

The two dylibs are pinned by checksum in `runtime-lock.json`'s `external`
overlays, like the other libraries Wine loads. `make runtime` builds each
release on the last one it restores, so they come from that base once a
published runtime carries them. Until then, `build-runtime.sh` fills the gap from
`.kosmickrisp`:

```sh
make kosmickrisp     # .kosmickrisp/libvulkan.1.dylib, libvulkan_kosmickrisp.dylib
make runtime         # r19: Wine 11.18 on r18's base, plus these two
```

To move to a newer Mesa or loader, change the lock, run `make kosmickrisp`,
put the checksums it prints into `runtime-lock.json`, bump `runtimeRevision`,
and build with `tools/wine-runtime/build-runtime.sh --vulkan .kosmickrisp`.
Naming `--vulkan` outright replaces the base's copies. `assemble.sh` refuses any
build whose checksums do not match the lock.

## What was checked

On an M4 Max with macOS 27, in a runtime assembled this way, a 32-bit D3D9 test
drew 500 fixed-function `DrawPrimitiveUP` triangles a frame for 1,500 frames
through the shipped DXVK, once on each driver, without errors. Uncapped frame
rates were in the same range for both and too noisy to rank either one. The
real client is the test that counts.
