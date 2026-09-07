# ROSilicon

A native macOS launcher for the Ragnarok Online LATAM Windows client on Apple
Silicon. One window: it installs everything and runs the game.

It ships the Wine runtime from
[WoWSilicon](https://github.com/WoWSilicon/WoWSilicon) inside the app, with
`x87sidecar` for the client's legacy x87 floating-point code, and DXVK for
Direct3D 9. Nothing but the game client is downloaded at install time.

## Build

```sh
make restore        # -> .wine-runtime, the pinned Wine tree (once)
make                # -> ROSilicon.app in this folder
make dmg            # -> the app and ROSilicon-<VERSION>.dmg
make bundle         # -> validates the Wine runtime, then the app and the .dmg
make app-no-wine    # -> the app without Wine: UI work only, cannot install
```

Needs Xcode (or the Swift toolchain); macOS 14+, Apple Silicon, Rosetta 2. The
script builds the package, assembles the bundle — the Wine runtime from
`.wine-runtime` included — draws the icon and ad-hoc signs it, without the
hardened runtime, so the launcher can pass `DYLD_LIBRARY_PATH` down to Wine. Set
`APP_OUT` to build elsewhere and `WINE_RUNTIME` to ship a Wine tree from
somewhere other than `.wine-runtime`. The version is read from the `VERSION`
file, and names both the bundle and the disk image.

The runtime goes in *before* the signature, since `codesign` seals everything
under `Resources/`, and the [wintrust patch](#the-wintrust-patch) is applied to
it there and then — by the launcher's own code, through the `--patch-wintrust`
flag its binary answers, so there is one implementation of the patch and not
two. The tree in `.wine-runtime` is left untouched, and still matches the
runtime lock `make bundle` validates it against.

`make restore` fetches the pinned tree published by WoWSilicon and checks it
against `Packaging/WineRuntime/artifact-lock.json`; `tools/wine-runtime/` also
holds the scripts that build one from source.

The disk image is the one to hand to someone else: it opens on a window holding
the app beside a shortcut to `/Applications` to drag it onto, and wears the app's
own icon. Laying that window out is the Finder's job, so the first build asks for
permission to control it; refusing costs only the icon positions, and the image
is built either way.

## What it does

The app is self-contained and installs into
`~/Library/Application Support/ROSilicon`:

```
wine/              the prefix; the game lands in drive_c/Gravity/Ragnarok
downloads/         in-progress downloads, removed when they finish
```

That is all of it. Wine, DXVK, the Steam stub and `x87sidecar` are read where
they lie inside `ROSilicon.app` — patched, signed and never written to, so the
signature holds and the app works wherever it sits, `/Applications` included.
The prefix links to the two Windows binaries rather than holding copies, and
those links are rewritten on every launch, so they follow the app if it moves.
Replacing the app is what updates any of it; nothing on disk needs migrating,
and the copies an older version left behind are removed on the next install.

**Install** starts by checking Rosetta 2 — everything below the launcher is x86
code, so a Mac without it is told in a second rather than after several
gigabytes — and then runs three stages, each skipped when it is already done:

1. **What the app carries** — nothing to install: it names the Wine version
   inside the app, checks DXVK, the Steam stub and `x87sidecar` are there,
   clears the quarantine flag a download may have left on them, and probes
   `x87sidecar` against the Rosetta build on this machine.
2. **The Wine prefix** — `wineboot --init`. It inherits the
   [wintrust patch](#the-wintrust-patch) from the runtime, so there is no
   patching stage.
3. **The game client** — reads size and MD5 from the server's headers,
   downloads with resume, verifies, extracts.

**Play** links DXVK and the Steam stub into the prefix and starts the client
through `steam.exe`, which is what the client expects to find running.

The `…` menu holds the rest: show the installation or game folder, reinstall the
client, change the client URL, copy the log, and clear the installation (to the
Trash, after a confirmation).

## The wintrust patch

The client's copy-protection component calls `WinVerifyTrust` on
`C:\windows\system32\ntdll.dll`. Under Wine that file is Wine's own unsigned
reimplementation, so the call fails with
`TRUST_E_NOSIGNATURE` and the client aborts — a false positive by construction,
since Wine's DLLs can never carry a Microsoft signature.
[WintrustPatch.swift](Sources/ROSilicon/WintrustPatch.swift) rewrites the
first bytes of the exported `WinVerifyTrust` and `WinVerifyTrustEx` to
`return 0`, keeping the original beside each file as `wintrust.dll.wine-orig`.

`build.sh` applies it once, to the runtime it bundles, through the launcher's
own `--patch-wintrust` flag — so the app ships patched and the launcher never
patches anything. This Wine copies its DLLs into each prefix rather than
symlinking them, and loads the prefix's copy in preference to the runtime's, so
a prefix created from that runtime is born patched too. The launcher neither
applies nor reports it — there is nothing for it to decide. The way back is to
rebuild the app from the untouched tree in `.wine-runtime`, or to put the
`wintrust.dll.wine-orig` kept beside each patched DLL back by hand.

## Languages

The window, the log and the error messages are translated into **English**,
**Portuguese (Brazil)** and **Spanish**; macOS picks the one matching the
reader's language and falls back to English for anything a translation is
missing. Every Portuguese variant resolves to `pt-BR` and every Spanish one to
`es`, so a reader set to `pt-PT` or `es-MX` still gets their own language.

Each string lives once in [Strings.swift](Sources/ROSilicon/Strings.swift)
and once per language in `Resources/Localizations/<lang>.lproj/Localizable.strings`.
To add a language, copy `en.lproj` to, say, `fr.lproj`, translate the values, and
build — `build.sh` picks up every `.lproj` it finds and lists them in the bundle.

## Layout

```
VERSION                  the version the build stamps into the app and the .dmg
Package.swift            SwiftPM manifest (macOS 14+, Swift 6)
build.sh                 builds, assembles and signs the .app, packs the .dmg
makeicon.swift           draws AppIcon.icns, no asset files needed
Makefile                 names the builds; build.sh does the work
Packaging/WineRuntime/   the runtime and artifact locks, and the Wine patches
tools/wine-runtime/      build, assemble, validate, package and restore the runtime
.wine-runtime/           the Wine tree the app ships (gitignored, `make restore`)
Resources/
  d9vk/d3d9.dll          Direct3D 9 to Vulkan, bundled into the app
  steam_stub/            the Steam stub the client expects, with its source
  x87sidecar/            the x87 hook, bundled into the app
  Localizations/         en.lproj, pt-BR.lproj, es.lproj
Sources/ROSilicon/
  Paths.swift            paths, the bundled runtime, the Wine environment
  Shell.swift            subprocesses with streamed output and cancellation
  Rosetta.swift          whether Rosetta 2 is installed on this Mac
  Downloader.swift       resumable ranged downloads, retries, md5
  WintrustPatch.swift    the signature-check workaround
  Installer.swift        the install stages
  GameRunner.swift       the launch path
  Status.swift           what is installed right now
  LauncherModel.swift    state and actions behind the window
  ContentView.swift      the window
  LauncherApp.swift      the window's scene and menu commands
  main.swift             the entry point, and the --patch-wintrust flag
  Strings.swift          every word the launcher shows
```

`RO_ROOT` overrides the install folder and `RO_TOOLS` the folder everything
bundled is read from — Wine included, since the runtime sits at `Wine/` under
it. Both are useful when running outside an app bundle.

## Credits

- **WoWSilicon** — [WoWSilicon/WoWSilicon](https://github.com/WoWSilicon/WoWSilicon)
  — the Wine runtime, `x87sidecar`, and the Rosetta work behind both.
- **x87sidecar / rosettax87_jit** — [Lifeisawful/rosettax87_jit](https://github.com/Lifeisawful/rosettax87_jit)
- **Wintrust patch** — [alexandrephz/ragnarok-no-linux](https://gitlab.com/alexandrephz/ragnarok-no-linux)
- **D9VK** — [Sikarugir-App/d9vk](https://github.com/Sikarugir-App/d9vk)
