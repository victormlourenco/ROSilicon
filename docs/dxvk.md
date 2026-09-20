# DXVK

Direct3D 9 reaches the GPU through DXVK, translated to Vulkan and then to Metal
by MoltenVK. The build is
[K0bin/dxvk](https://github.com/K0bin/dxvk)'s `moltenvk-version` branch — the
1.10 backend under the 2.3 D3D9 frontend, with the Metal workarounds that branch
carries — pinned by commit in
[Packaging/D9VK/source-lock.json](../Packaging/D9VK/source-lock.json), with the
patches in [Packaging/D9VK/patches/](../Packaging/D9VK/patches/) applied on top in
the order they are numbered. The source is not vendored; only the lock and the
patches are.

`make d9vk` clones that commit, patches it, cross-compiles a 32-bit `d3d9.dll`
into `.d9vk` and strips it. It needs more than the Steam stub does:

```sh
make d9vk-toolchain   # brew install mingw-w64 meson ninja glslang
```

DXVK is the one build product with a checked-in fallback. A clone and several
minutes of compiling is a lot to ask of someone who only wants to build the app,
so `Resources/d9vk/d3d9.dll` stays in the repository: `build.sh` ships `.d9vk`'s
copy when there is one and that one otherwise, and says which it took. `make
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

