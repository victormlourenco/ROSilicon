# DXVK

Direct3D 9 reaches the GPU through DXVK, translated to Vulkan and then to Metal
by MoltenVK, or by [KosmicKrisp](kosmickrisp.md) when the ⌥ menu asks for it.
The build is
[K0bin/dxvk](https://github.com/K0bin/dxvk)'s `moltenvk-version` branch — the
1.10 backend under the 2.3 D3D9 frontend, with the Metal workarounds that branch
carries — pinned by commit in
[Packaging/D9VK/source-lock.json](../Packaging/D9VK/source-lock.json), with the
patches in [Packaging/D9VK/patches/](../Packaging/D9VK/patches/) applied on top in
the order they are numbered. The source is not vendored; only the lock and the
patches are.

That build is MoltenVK's. KosmicKrisp gets K0bin/dxvk's `master` — current
DXVK — pinned by
[Packaging/D9VK/kosmickrisp/source-lock.json](../Packaging/D9VK/kosmickrisp/source-lock.json),
with the patches in
[Packaging/D9VK/kosmickrisp/patches/](../Packaging/D9VK/kosmickrisp/patches/):

- **0001** makes `geometryShader`, `fillModeNonSolid` and `depthClipEnable`
  optional. Master requires all three, and on the `main` KosmicKrisp is now
  built from only `depthClipEnable` is there, so unpatched it still finds no
  adapter. Where they are used it falls back: `ProcessVertices`, which emulates
  software vertex processing with a geometry shader, becomes a no-op; wireframe
  and point fill draw solid; and depth clip is had by turning depth clamp off,
  which on `main` is now the fallback that never runs. `moltenvk-version` does
  the same for the first two. Ragnarok uses none of them.
- **0002** is the `moltenvk-version` build's UP-draw patch, ported: every
  `DrawPrimitiveUP` used to bind its own slice of the UP buffer and unbind it
  after, and now the whole buffer stays bound and the draw moves `firstVertex`.
- **0003** adds `d3d9.apiStatsInterval`, off by default; see below.
- **0004** ignores `SetTransform` with the matrix already set, which otherwise
  re-uploads the fixed-function constants and rebinds their descriptors.
- **0005** keeps descriptor update templates on for 32-bit builds, as DXVK's own
  default intends; its option parser overrode that with off.
- **0006** and **0007** let a draw loop that alternates vertex formats — 2D and
  3D sprites, say — reuse the pipeline variant and the packed input layout it
  found last time, instead of hashing the whole pipeline state and repacking
  every fixed-function attribute on each switch.

KosmicKrisp itself carries two more, see [KosmicKrisp](kosmickrisp.md). On an
M4 Max, a Ragnarok-shaped test — 3,000 one-quad `DrawPrimitiveUP` sprites a
frame, 30% of them world-transformed, a texture change every four, with
presentation taken out of the timing — went from 6.0 ms a frame to 3.4 with all
of them, and drew the same pixels. The `moltenvk-version` build on MoltenVK does
it in 2.7: master on KosmicKrisp has no dynamic uniform buffers, so a constant
upload or a texture change still costs a descriptor set per draw.

Which of those paths the real client leans on is what `d3d9.apiStatsInterval`
is for. Set it, and the KosmicKrisp build logs per-frame counts of draws by kind
and primitive, vertex format, texture, transform and state changes every that
many seconds:

```sh
DXVK_CONFIG="d3d9.apiStatsInterval = 5"
```
The app carries both, `d3d9.dll` and `kosmickrisp/d3d9.dll`, and links the one
for the driver the run uses into the prefix on every launch, so the ⌥ menu's
**Vulkan Driver** picker — and `RO_VULKAN_DRIVER` ahead of it — switches the
DXVK along with the driver.

`make d9vk` clones each commit, patches it where its lock lists patches,
cross-compiles a 32-bit `d3d9.dll` into `.d9vk` (and `.d9vk/kosmickrisp`) and
strips it. It needs more than the Steam stub does:

```sh
make d9vk-toolchain   # brew install mingw-w64 meson ninja glslang
```

DXVK is the one build product with a checked-in fallback. A clone and several
minutes of compiling is a lot to ask of someone who only wants to build the app,
so `Resources/d9vk/d3d9.dll` and `Resources/d9vk/kosmickrisp/d3d9.dll` stay in
the repository: `build.sh` ships `.d9vk`'s copy of each when there is one and
the checked-in one otherwise, and says which it took. `make
bundle` builds and checks its own either way, so a release never goes out on the
fallback by accident.

`.d9vk/d3d9.dll` is the second real file target in the Makefile, rebuilt when a
patch or the source lock is newer and left alone otherwise, so an ordinary
`make` never runs the Windows compiler. `make clean` removes `.d9vk`, and `D9VK`
points somewhere other than it.

The patches are ours to carry, not upstream's to take back — they are aimed at
this client. Ragnarok is fixed-function D3D9 drawing thousands of sprite quads a
frame through `DrawPrimitiveUP`, and `d3d9.dll` is itself translated x86 running
under Rosetta, so DXVK's own per-draw cost and the number of Vulkan calls it
makes matter more here than they would on a native Vulkan driver.

