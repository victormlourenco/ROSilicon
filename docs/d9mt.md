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

## Getting a build

d9mt is **not built from this repository**, the only shipped piece that is
not. `make d9mt` stages one that already exists:

```sh
make d9mt D9MT_SOURCE=~/src/d9mt-v2     # -> .d9mt, then validated
make                                    # the app, with d9mt in it
```

`tools/d9mt/stage.sh` copies the seven products out of that checkout into
`.d9mt`, in the layout above, and checks the checkout is at the commit
[Packaging/D9MT/source-lock.json](../Packaging/D9MT/source-lock.json) pins.
That check is load-bearing: the tree carries no version string of its own, so
a staged `d3d9.dll` says nothing about which d9mt it is and the lock is the
only record. `--any-commit` is for working on d9mt itself.

Building the checkout is upstream's own five scripts, in order:

```sh
scripts/fetch-deps.sh            # vendors upstream DXVK's d3d9 frontend + dxbc-spirv
scripts/build-llvm-unixside.sh   # LLVM 15.0.7 as x86_64 static libs — the long one
scripts/build-d9mtair.sh         # the AIR emitter: d9mtair.so + its PE dlls
scripts/build-bridge.sh          # winemetal.so + its PE dlls, and the import lib
scripts/build-driver.sh          # d3d9.dll
```

It needs the mingw-w64 cross-compilers for both 32- and 64-bit, `glslang`,
`spirv-cross`, the Metal toolchain from Xcode, cmake and ninja. The LLVM build
is tens of minutes on its own.

## What is in the way

Four things, none of them in the launcher, all of them between a staged d9mt
and a release:

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

**The DXVK clone is not pinned.** `fetch-deps.sh` does a `--depth 1` clone of
`doitsujin/dxvk`'s `main`, so two stagings of the same d9mt commit are not the
same driver. The locked d9mt commit is only half a pin until that is fixed
upstream or worked around here.

**It is young.** Upstream's own notes describe the `d3d9.dll` link as having
become non-fatal only recently, and its `SA2-LAUNCH.md` reads like a driver
under active diagnosis. The client is the test that counts, and it has not
been run.

## What was checked

The launcher side, end to end, against a **stand-in** staging — real binaries
of each of the three machines, standing in for d9mt's own:

- `make d9mt` refuses a checkout that is not at the locked commit, and one
  that has not been built, naming the missing products.
- `validate.sh` rejects a DXVK `d3d9.dll` staged as d9mt, since no DXVK
  imports `winemetal.dll`, and rejects a piece built for the wrong machine.
- `build.sh` stages the driver into `Resources/d9mt/` and overlays the six
  builtins into the bundled Wine tree, and the signature over the result
  verifies — which was the open question, the tree being sealed.
- An app built without a staging ships without d9mt, and the picker is hidden
  rather than offering a backend that is not there.

Not checked, because no d9mt was built: anything d9mt itself does. No client
has been launched on it.
