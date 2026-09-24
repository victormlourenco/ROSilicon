# Building ROSilicon

Everything below is for working on the launcher itself. To *play* the game you
only need the disk image from the [releases page](https://github.com/victormlourenco/ROSilicon/releases)
— see the [README](../README.md).

```sh
make restore        # -> .wine-runtime, the pinned Wine tree (once)
make runtime        # -> .wine-runtime built from source instead (see below)
make steam-stub     # -> .steam-stub, the cross-compiled Steam stub (once)
make d9vk           # -> .d9vk, DXVK's d3d9.dll built from source (see below)
make kosmickrisp    # -> .kosmickrisp, the Vulkan loader and driver for the
                    #    runtime, built from source (see kosmickrisp.md)
make                # -> ROSilicon.app in this folder
make dmg            # -> the app and ROSilicon-<VERSION>.dmg
make bundle         # -> checks the runtime, builds and checks the stub and
                    #    DXVK, then the app and the .dmg
make app-no-wine    # -> the app without Wine: UI work only, cannot install
```

Needs Xcode 26 or newer — the interface is built on Liquid Glass, which only
exists from the macOS 26 SDK — and mingw-w64 once for the
[Steam stub](steam-stub.md), plus meson, ninja and glslang to build
[DXVK](dxvk.md), which `make bundle` does and an ordinary `make` does not;
Apple Silicon and Rosetta 2. That is what builds
it; what it *runs* on is still macOS 14 and up, where it falls back to a frosted
material. The
script builds the package, assembles the bundle — the Wine runtime from
`.wine-runtime` included — draws the icon and ad-hoc signs it, without the
hardened runtime, so the launcher can pass `DYLD_LIBRARY_PATH` down to Wine. Set
`APP_OUT` to build elsewhere and `WINE_RUNTIME` to ship a Wine tree from
somewhere other than `.wine-runtime`, or `STEAM_STUB` for the Steam stub. The
version is read from the `VERSION` file, and names both the bundle and the disk
image.

The runtime goes in *before* the signature, since `codesign` seals everything
under `Resources/`. It goes in as it is, the
[wintrust patch](wine-runtime.md#the-wintrust-patch) already built into it, so the bundle's
copy matches the tree in `.wine-runtime` and the runtime lock `make bundle`
validates that against.

`make restore` fetches the pinned tree from the releases of the repository
`Packaging/WineRuntime/artifact-lock.json` names, and checks it against that
lock; [The Wine runtime](wine-runtime.md) says how one is built.

The disk image is the one to hand to someone else: it opens on a window holding
the app beside a shortcut to `/Applications` to drag it onto, and wears the app's
own icon. Laying that window out is the Finder's job, so the first build asks for
permission to control it; refusing costs only the icon positions, and the image
is built either way.

## Testing

```sh
swift test
swift build -c release
```

Automated tests use an injected registry runner and isolated preference domains;
they do not launch Wine, download the client, or modify a real Wine prefix. What
they cannot cover is checked by hand against a disposable install root (`RO_ROOT`)
— [Keyboard](keyboard.md#verifying-by-hand) says how, for the one feature where
a passing test proves the least.

