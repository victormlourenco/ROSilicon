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
make d9mt-toolchain     # once: mingw-w64, glslang, spirv-cross, cmake, ninja, llvm@15
make d9mt               # -> .d9mt, built from the pinned sources and validated
make                    # the app, with d9mt in it
```

Most of an hour the first time, nearly all of it LLVM. The work folder is kept,
so a second `make d9mt` is only d9mt's own three build scripts — a couple of
minutes. `D9MT_WORK=<dir>` puts it outside `.build`, where `make clean` will
not take the LLVM with it.

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

Two LLVMs are required, for different sides, which is the prerequisite nobody
guesses: `build-llvm-unixside.sh` builds LLVM 15 as **x86_64 static libs** for
the AIR emitter on Wine's unix side, with `LLVM_BUILD_TOOLS=Off` and therefore
no `llvm-config` — while `build-air-compiler.sh`, which `build-bridge.sh` runs
for its smoke test, needs a **host** `llvm-config` and looks for Homebrew's
`llvm@15` by absolute path. Another version will not do; the AIR compiler
includes LLVM 15's headers.

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

The launcher side, end to end, against a **stand-in** staging — real binaries
of each of the three machines, standing in for d9mt's own:

- `make d9mt D9MT_SOURCE=…` refuses a checkout that is not at the locked
  commit, and one that has not been built, naming the missing products.
- `make d9mt`'s toolchain gate catches a missing `llvm@15`, and its pinned
  checkouts were exercised against GitHub: a shallow fetch of a non-tip
  commit, an idempotent second run, and a refusal when something that is not
  a checkout is in the way. The build itself has not been run end to end.
- `validate.sh` rejects a DXVK `d3d9.dll` staged as d9mt, since no DXVK
  imports `winemetal.dll`, and rejects a piece built for the wrong machine.
- `build.sh` stages the driver into `Resources/d9mt/` and overlays the six
  builtins into the bundled Wine tree, and the signature over the result
  verifies — which was the open question, the tree being sealed.
- An app built without a staging ships without d9mt, and the picker is hidden
  rather than offering a backend that is not there.

Not checked, because no d9mt was built: the hour-long build as a whole, and
anything d9mt itself does. No client has been launched on it.
