# d9mt

[DXVK](dxvk.md) turns the client's Direct3D 9 into Vulkan, and a Vulkan
driver — MoltenVK or [KosmicKrisp](kosmickrisp.md) — turns that into Metal.
[d9mt](https://github.com/neo773/d9mt-v2) replaces that whole stack: it is
DXVK 3.0's Direct3D 9 state tracker with a Metal backend bolted straight on,
with no Vulkan anywhere — its own build refuses to compile if a `Vk` type
reaches real code. One translation instead of two, and no portability layer in
between to lose a feature or a compiler. The ⌥ menu's **Direct3D 9 Backend**
picker is how it gets tried.

It is experimental, and the launcher treats it that way: it is the one thing
the app ships only when a build was handed one, the picker hides itself where
it was not, and DXVK stays the default. **Nothing from it may go into a
release yet** — see [What is in the way](#what-is-in-the-way).

## What picking it changes

Three things, all of them in `D3D9Backend`:

- **`d3d9.dll`.** `prepare()` links one DLL into the prefix's `syswow64`, and
  d9mt's is a whole Direct3D 9 implementation rather than a front end for one.
  `Paths.d3d9DLL(for:vulkan:)` is where the two part ways.
- **The builtins Wine loads.** d9mt's PE side reaches Metal through
  `winemetal` — vendored from [DXMT](https://github.com/3Shain/dxmt) — and
  compiles shaders through `d9mtair`, its AIR emitter. Both are Wine builtins,
  a PE DLL and a Mach-O unixlib each, so `WINEDLLOVERRIDES` names them beside
  `d3d9=n,b`.
- **The Vulkan driver stops mattering.** d9mt loads none, so
  `MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS`, `DXVK_ASYNC` and the log line naming
  the driver are all skipped, and the **Vulkan Driver** picker hides itself
  while d9mt is selected. `VK_DRIVER_FILES` is still set for everything else
  in the prefix — `wineboot` and `winecfg` have their own reasons to find a
  GPU.

`RO_D3D9_BACKEND` names a backend from a terminal, ahead of whatever the menu
remembers, the same way `RO_VULKAN_DRIVER` does for the driver:

```sh
RO_D3D9_BACKEND=d9mt open ROSilicon.app
```

The game's log names the backend it got. Metal's frame-rate overlay works
either way: Metal is the last hop whichever backend ran.

## Where the pieces go

Seven files, and the awkward part is that six of them do not belong in
`Resources/` at all. Wine loads builtins out of its own `lib/wine`, so they
have to be *inside the bundled Wine tree* — and
[`Paths.wineRoot`](../Sources/ROSilicon/Paths.swift) is in the app bundle,
under the signature, where nothing writes after the build. So `build.sh`
overlays them while it is assembling, before `codesign` seals `Resources/`:

```
Resources/d9mt/d3d9.dll                        the driver, i686 PE
Resources/Wine/lib/wine/i386-windows/winemetal.dll
Resources/Wine/lib/wine/i386-windows/d9mtair.dll
Resources/Wine/lib/wine/x86_64-windows/…       the same two, for 64-bit programs
Resources/Wine/lib/wine/x86_64-unix/winemetal.so   where Metal actually is
Resources/Wine/lib/wine/x86_64-unix/d9mtair.so     and LLVM with it
```

Three machines at once, which is what `tools/d9mt/validate.sh` mostly checks:
the client is 32-bit, other programs in the prefix are not, and Wine's unix
side runs x86_64 under Rosetta. A piece built for the wrong one loads nowhere,
and Wine then quietly falls back to its own D3D9 — playable, slow, and noticed
by nobody.

`D3D9Backend.isD9MTBundled` asks for both halves — the driver and
`winemetal.so` — because a `d3d9.dll` whose bridge is missing loads fine and
dies on its first draw. One half present is not a backend, so the picker stays
hidden.

## Building it

```sh
make d9mt-toolchain     # once: bash, mingw-w64, glslang, spirv-cross, cmake,
                        #       ninja, llvm@15, and Xcode's Metal toolchain
make d9mt               # -> .d9mt, built from the pinned sources and validated
make                    # the app, with d9mt in it
```

Most of an hour the first time, nearly all of it LLVM. The work folder —
`.d9mt-build`, or wherever `D9MT_WORK` names — is kept, so a second
`make d9mt` is only d9mt's own three build scripts, a couple of minutes.

It sits outside `.build` and `make clean` leaves it alone, which is not
tidiness but damage control: a clean while this is running deletes the pack
git is writing and the LLVM clone dies with `invalid index-pack output`, which
reads like a network fault and is not one. Remove it by hand for the space.

It also needs **CrossOver installed**, which Homebrew cannot supply:
`build-bridge.sh` links the unix side against
`/Applications/CrossOver.app`'s `ntdll.so` and refuses without it.
`tools/d9mt/build.sh` checks for it before the hour rather than after.

### Why a script was needed

d9mt builds with its own five scripts, and they resolve `$ROOT` as the parent
of the checkout — v2 was extracted out of d9mt **v1** and kept the references.
So a bare `git clone` of d9mt-v2 cannot build. It wants v1 around it, a
[dxmt](https://github.com/3Shain/dxmt) checkout beside that, and a DXVK clone
*inside* it that none of its own scripts creates, though `build-driver.sh`'s
link reads `d3d9.def` out of it:

```
<work>/d9mt/                           v1 — $ROOT: tools/, vendor/, prebuilt/
<work>/d9mt/d9mt-v2/                   the d9mt-v2 checkout, at the locked commit
<work>/d9mt/d9mt-v2/DXVK-3.0-uptsream  the extraction source (upstream's spelling)
<work>/d9mt/d9mt-v2/toolchains/        the x86_64 LLVM, built once and kept
<work>/dxmt/                           for -I src/airconv
```

Beside v1 rather than *at* `<work>/d9mt/v2`, which is the trap: v1 carries a
tracked `v2/` of its own — an older in-repo version of the same thing, the one
the stale `scripts/build.sh` still targets — and the standalone repository is
what replaced it. Only the checkout's parent matters to its scripts, so the
folder is named after the repository and v1's `v2/` is left where it is.

Getting that wrong is worse than failing. `tools/make-builtin.py` — v1's, and
what marks the PE DLLs as Wine builtins — is read behind an `if [ -f ]`, so a
v2 checkout in the wrong place builds, stages and ships, and then the builtins
never load. That is the trap the script exists to close.

All four sources are pinned by commit in
[Packaging/D9MT/source-lock.json](../Packaging/D9MT/source-lock.json), the DXVK
clone included: `fetch-deps.sh` would otherwise clone whatever `main` was that
day, which made two stagings of one d9mt commit different drivers. The script
clones the pinned commit first and hands `fetch-deps.sh` the result, which it
accepts because it only clones when the folder is not already a checkout.

### The four prerequisites that are not obvious

**Two LLVMs, for different sides.** `build-llvm-unixside.sh` builds LLVM 15 as **x86_64 static libs** for
the AIR emitter on Wine's unix side, with `LLVM_BUILD_TOOLS=Off` and therefore
no `llvm-config` — while `build-air-compiler.sh`, which `build-bridge.sh` runs
for its smoke test, needs a **host** `llvm-config` and looks for Homebrew's
`llvm@15` by absolute path. Another version will not do; the AIR compiler
includes LLVM 15's headers.

**A bash newer than the one macOS ships.** `build-d9mtair.sh` declares a
`local -n` nameref, which is bash 4.3; macOS ships 3.2, so the system bash
dies on `local: -n: invalid option`. Finding a modern one is not enough
either, since `build-bridge.sh` runs `build-d9mtair.sh` itself with a plain
`bash` — so build.sh puts the modern one on `PATH` ahead of `/bin` rather than
only naming it.

**Xcode's Metal compiler, which is a download.** From Xcode 26 `metal` is a
separately downloaded component: the binary is always on disk as a stub that
says `cannot execute tool 'metal' due to missing Metal Toolchain`. The gate
therefore *runs* it rather than locating it, since the driver compiles the
fixed-function ubershaders and the meta-blit to `metallib` and there is no
building it without one. `make d9mt-toolchain` fetches it
(`xcodebuild -downloadComponent MetalToolchain`, ~840 MB).

**A submodule two levels down.** `dxbc-spirv` carries SPIRV-Headers as
`submodules/spirv_headers` and includes it by relative path, but
`fetch-deps.sh` inits `dxbc-spirv` without recursing — so the folder arrives
as an empty stub and the failure lands much later, in the smoke test at the
end of the bridge build, as a missing `spirv.hpp`. build.sh inits it in the
DXVK clone before `fetch-deps.sh` copies the tree.

### The patch it carries

One, ours, in
[Packaging/D9MT/patches/](../Packaging/D9MT/patches/) and listed in the lock.

Metal has no ARGB4444, so DXMT's bridge carries a corrected constant for it —
`WMTPixelFormatBGRA4Unorm = GBARSwizzle | ABGR4Unorm` — but the driver's own
`MtlFormat` enum holds only the bare `ABGR4Unorm`, so it can never ask for the
correction. `A4R4G4B4` and `X4R4G4B4` therefore sampled with their channels
rotated: red took alpha's value, green took red's, blue took green's, and
**alpha took blue's**. Anything with blue in it came out opaque.

That is two visible bugs from one line. The transparent parts of sprite quads
turned into solid boxes, tinted toward cyan because red carried alpha, which is
zero where a sprite is transparent. And the ground lightmap — colour black,
intensity in alpha — sampled as `(intensity, 0, 0)`, which the ground pass's
`MODULATE2X` turned into a saturated red that erased the cobblestone entirely.
Turning the lightmap off in the client with `/lightmap` was what separated the
two and made the format the suspect.

`X1R5G5B5` directly beside them already carries a swizzle, so this is an
omission rather than a decision. It is not upstream yet and is worth sending.

The checkout is reset to the locked commit and the patches reapplied on every
build, so what it builds is always commit + patches rather than a
half-remembered edit — work on the patches, not on the tree. `--no-patch` is
the escape hatch while iterating on a fix by hand, before it becomes one. The
reset also reverts the two generated metallib headers that are committed
upstream, and `build-driver.sh` decides to regenerate them by mtime, so
build.sh touches that script to keep the shaders the ones this Mac's Metal
toolchain produces. Those metallibs embed a per-compile hash, which is why two
builds of the same source give the same `d3d9.dll` size and different bytes.

### Staging a checkout you built yourself

`D9MT_SOURCE` skips the build and stages a checkout whose own scripts have
already run, which is what to use while working on d9mt itself:

```sh
make d9mt D9MT_SOURCE=~/projects/d9mt/d9mt-v2
```

`tools/d9mt/stage.sh` copies the seven products out into `.d9mt` in the layout
above, and checks the checkout is at the locked commit. That check is
load-bearing: the tree carries no version string of its own, so a staged
`d3d9.dll` says nothing about which d9mt it is and the lock is the only record.
`--any-commit` stages one that is not.

## What is in the way

Three things, none of them in the launcher, all of them between a staged d9mt
and a release. (A fourth, `fetch-deps.sh` cloning DXVK's `main` unpinned, is
now worked around: `tools/d9mt/build.sh` clones the pinned commit itself.)

**No license.** The repository declares none. Its `driver/` is extracted
DXVK 3.0, which is zlib, and its `bridge/` is vendored winemetal from DXMT,
but the tree itself says nothing — so there is no permission to redistribute
it inside this GPL-3.0 app. This is the blocker that does not depend on how
well it runs.

**It was built against CrossOver's Wine.** Every one of its scripts points at
`/Applications/CrossOver.app`, and `build-bridge.sh` links the unix side
against that tree's `ntdll.so`. The link is `-undefined dynamic_lookup`, so
nothing binds to those files — but the Wine unixlib ABI the bridge was
compiled for is CrossOver's, and the runtime here is Wine 11.18.
`validate.sh` cannot check that two libraries agree about a calling
convention, and a disagreement is a crash inside `__wine_unix_call`, not a
diagnostic. Retargeting the bridge build onto `.wine-runtime` is the real fix.

**It is young.** Upstream's own notes describe the `d3d9.dll` link as having
become non-fatal only recently, and its `SA2-LAUNCH.md` reads like a driver
under active diagnosis. The client is the test that counts, and it has not
been run.

## What was checked

**`make d9mt` builds and stages d9mt, from nothing.** All seven products, out
of the four pinned sources, validated: `d3d9.dll` links with all 20 of
`d3d9.def`'s exports, and the bridge's PE halves come out marked as Wine
builtins, which is what says `$ROOT` resolved to v1 as it has to.

```
d3d9.dll                          PE32 i386        75 MB, 20 exports
wine/i386-windows/winemetal.dll   PE32 i386
wine/i386-windows/d9mtair.dll     PE32 i386
wine/x86_64-windows/…             PE32+ x86-64     the same two
wine/x86_64-unix/winemetal.so     Mach-O x86_64    13 MB
wine/x86_64-unix/d9mtair.so       Mach-O x86_64    11 MB, LLVM and all
```

The launcher side was checked end to end earlier, against a stand-in staging
(real binaries of each of the three machines) and now against the real one:

- `validate.sh` rejects a DXVK `d3d9.dll` staged as d9mt, since no DXVK
  imports `winemetal.dll`, and rejects a piece built for the wrong machine.
- `build.sh` stages the driver into `Resources/d9mt/` and overlays the six
  builtins into the bundled Wine tree, and the signature over the result
  verifies — which was the open question, the tree being sealed.
- An app built without a staging ships without d9mt, and the picker is hidden
  rather than offering a backend that is not there.
- `make d9mt D9MT_SOURCE=…` refuses a checkout that is not at the locked
  commit, and one that has not been built, naming the missing products.
- The pinned checkouts were exercised against GitHub: a shallow fetch of a
  non-tip commit, an idempotent second run, and a refusal when something that
  is not a checkout is in the way.

**The client runs on it, and renders.** Ragnarok reaches the login screen and
plays, which is as far as anyone has taken it here. What that first run showed
was the 4444 channel rotation above, now patched and confirmed fixed in the
client; `make d9mt` reproduces it from the lock.

Not checked: how far the client gets beyond that, and how fast. No comparison
against DXVK has been made, and the licensing blocker above is untouched by any
of this.
