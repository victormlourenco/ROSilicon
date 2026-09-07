# ROSilicon

A native macOS launcher for the Ragnarok Online LATAM Windows client on Apple
Silicon. One window: it installs everything and runs the game.

It uses the Wine build from
[WoWSilicon](https://github.com/WoWSilicon/WoWSilicon) with `x87sidecar` for the
client's legacy x87 floating-point code, and DXVK for Direct3D 9.

## Build

```sh
./build.sh          # -> ROSilicon.app and ROSilicon-0.0.1.dmg in this folder
./build.sh --no-dmg # -> just the app
```

Needs Xcode (or the Swift toolchain); macOS 14+, Apple Silicon, Rosetta 2. The
script builds the package, assembles the bundle, draws the icon and ad-hoc signs
it — without the hardened runtime, so the launcher can pass
`DYLD_LIBRARY_PATH` down to Wine. Set `APP_OUT` to build elsewhere. The version
is read from the `VERSION` file, and names both the bundle and the disk image.

The disk image is the one to hand to someone else: it opens on a window holding
the app beside a shortcut to `/Applications` to drag it onto, and wears the app's
own icon. Laying that window out is the Finder's job, so the first build asks for
permission to control it; refusing costs only the icon positions, and the image
is built either way.

## What it does

The app is self-contained and installs into
`~/Library/Application Support/ROSilicon`:

```
WoWSilicon.app/    the Wine build, downloaded on first install
wine/              the prefix; the game lands in drive_c/Gravity/Ragnarok
tools/             d3d9.dll and steam_stub.exe, copied out of the app
downloads/         in-progress downloads, removed when they finish
```

**Install** starts by checking Rosetta 2 — everything below the launcher is x86
code, so a Mac without it is told in a second rather than after several
gigabytes — and then runs four stages, each skipped when it is already done:

1. **The Wine build** — downloads the pinned WoWSilicon disk image, mounts it,
   copies the app out, clears the quarantine flag, and checks `x87sidecar`
   against the Rosetta build on this machine.
2. **The Wine prefix** — `wineboot --init`.
3. **The signature-check workaround** — patches every `wintrust.dll`, in the
   Wine build and in the prefix (see below).
4. **The game client** — reads size and MD5 from the server's headers,
   downloads with resume, verifies, extracts.

**Play** links DXVK and the Steam stub into the prefix and starts the client
through `steam.exe`, which is what the client expects to find running.

The `…` menu holds the rest: show the installation or game folder, reinstall the
client, re-apply or restore the wintrust patch, change the client URL, copy the
log, and clear the installation (to the Trash, after a confirmation).

## The wintrust patch

The client's copy-protection component calls `WinVerifyTrust` on
`C:\windows\system32\ntdll.dll`. Under Wine that file is Wine's own unsigned
reimplementation, so the call fails with
`TRUST_E_NOSIGNATURE` and the client aborts — a false positive by construction,
since Wine's DLLs can never carry a Microsoft signature.
[WintrustPatch.swift](Sources/ROSilicon/WintrustPatch.swift) rewrites the
first bytes of the exported `WinVerifyTrust` and `WinVerifyTrustEx` to
`return 0`, keeping the original beside each file as `wintrust.dll.wine-orig`.
This Wine copies its DLLs into each prefix rather than symlinking them, so the
build *and* the prefix are patched.

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
Resources/
  d9vk/d3d9.dll          Direct3D 9 to Vulkan, bundled into the app
  steam_stub/            the Steam stub the client expects, with its source
  Localizations/         en.lproj, pt-BR.lproj, es.lproj
Sources/ROSilicon/
  Paths.swift            pinned versions, URLs, paths, the Wine environment
  Shell.swift            subprocesses with streamed output and cancellation
  Rosetta.swift          whether Rosetta 2 is installed on this Mac
  Downloader.swift       resumable ranged downloads, retries, md5
  WintrustPatch.swift    the signature-check workaround
  Installer.swift        the install stages
  GameRunner.swift       the launch path
  Status.swift           what is installed right now
  LauncherModel.swift    state and actions behind the window
  ContentView.swift      the window
  LauncherApp.swift      the app entry point
  Strings.swift          every word the launcher shows
```

`RO_ROOT` overrides the install folder and `RO_TOOLS` the folder the bundled
binaries are read from — both useful when running outside an app bundle.

## Credits

- **WoWSilicon** — [WoWSilicon/WoWSilicon](https://github.com/WoWSilicon/WoWSilicon)
  — the Wine build, `x87sidecar`, and the Rosetta work behind both.
- **x87sidecar / rosettax87_jit** — [Lifeisawful/rosettax87_jit](https://github.com/Lifeisawful/rosettax87_jit)
- **Wintrust patch** — [alexandrephz/ragnarok-no-linux](https://gitlab.com/alexandrephz/ragnarok-no-linux)
- **D9VK** — [Sikarugir-App/d9vk](https://github.com/Sikarugir-App/d9vk)
