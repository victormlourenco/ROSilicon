# ROSilicon

A native macOS launcher for the Ragnarok Online LATAM Windows client on Apple
Silicon. One window: it installs everything and runs the game.

It ships [its own build of Wine](#the-wine-runtime) inside the app —
[WineAndAqua](https://github.com/WineAndAqua/wine)'s macOS Wine, with patches
that are mostly [WoWSilicon](https://github.com/WoWSilicon/WoWSilicon)'s — with
`x87sidecar` for the client's legacy x87 floating-point code (or
[`rosettax87_jit`](#x87-translation), chosen behind ⌥), and DXVK for Direct3D 9.
Nothing but the game client is downloaded at install time.

## Build

```sh
make restore        # -> .wine-runtime, the pinned Wine tree (once)
make runtime        # -> .wine-runtime built from source instead (see below)
make steam-stub     # -> .steam-stub, the cross-compiled Steam stub (once)
make                # -> ROSilicon.app in this folder
make dmg            # -> the app and ROSilicon-<VERSION>.dmg
make bundle         # -> validates the Wine runtime, then the app and the .dmg
make app-no-wine    # -> the app without Wine: UI work only, cannot install
```

Needs Xcode (or the Swift toolchain), and mingw-w64 once for the
[Steam stub](#the-steam-stub); macOS 14+, Apple Silicon, Rosetta 2. The
script builds the package, assembles the bundle — the Wine runtime from
`.wine-runtime` included — draws the icon and ad-hoc signs it, without the
hardened runtime, so the launcher can pass `DYLD_LIBRARY_PATH` down to Wine. Set
`APP_OUT` to build elsewhere and `WINE_RUNTIME` to ship a Wine tree from
somewhere other than `.wine-runtime`, or `STEAM_STUB` for the Steam stub. The
version is read from the `VERSION` file, and names both the bundle and the disk
image.

The runtime goes in *before* the signature, since `codesign` seals everything
under `Resources/`. It goes in as it is, the
[wintrust patch](#the-wintrust-patch) already built into it, so the bundle's
copy matches the tree in `.wine-runtime` and the runtime lock `make bundle`
validates that against.

`make restore` fetches the pinned tree from the releases of the repository
`Packaging/WineRuntime/artifact-lock.json` names, and checks it against that
lock; [The Wine runtime](#the-wine-runtime) says how one is built.

The disk image is the one to hand to someone else: it opens on a window holding
the app beside a shortcut to `/Applications` to drag it onto, and wears the app's
own icon. Laying that window out is the Finder's job, so the first build asks for
permission to control it; refusing costs only the icon positions, and the image
is built either way.

## What it does

The app is self-contained and installs into
`~/Library/Application Support/ROSilicon`:

```
wine/              the default profile's prefix; the game lands in drive_c/Gravity/Ragnarok
profiles/<name>/   each additional profile's prefix, laid out the same way
downloads/         in-progress downloads, removed when they finish
```

That is all of it. Wine, DXVK, the Steam stub and the x87 hooks are read where
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

Play stays available while the game runs: each press opens another client in
the same prefix, with the settings of that moment. For a few seconds after each
press the button shows a spinner and ignores further presses, so a double click
opens one client, not two. A link already pointing at
the app is left alone, so a second launch never pulls DXVK out from under a
client that is starting. Every `steam.exe` waits for the last client to close,
so the launcher shows the game as running until then, whichever was started
first. **Quit Game** shuts all of them down, since it stops everything in the
prefix.

The `…` menu holds the rest: show the installation or game folder, reinstall the
client, change the client URL, copy the log, and clear the installation (to the
Trash, after a confirmation). Holding ⌥ also reveals `WINEDEBUG` (`-all` by
default, so Wine stays quiet) and a field for extra `NAME=value` variables
separated by `;`. Both are remembered, applied after everything the launcher
sets itself — so they can override it — and take effect on the next launch.

## Profiles

Each profile is a Wine prefix of its own — its own game client, registry and
settings — chosen from the menu beside `…`. The default profile is `wine/`, the
prefix every install had before there were profiles, so an existing install
carries on as it was. It is always there and cannot be deleted.

**New Profile…** asks for a name and makes `profiles/<name>/`, which is all a
profile is: the launcher keeps no list of them, so the folders under
`profiles/` are the profiles. A new one starts empty, and **Install** boots its
prefix and downloads a client into it, the same as for the default profile on
a fresh install. Names are kept as typed, trimmed; they cannot start with a dot
or contain `/` or `:`, and cannot match another profile's name in any case.

**Delete Profile…** moves the chosen profile's folder to the Trash, after a
confirmation, and switches back to the default profile; for the default profile
it is disabled. **Clear Installation Folder** still takes everything, every
profile included.

The chosen profile is remembered between launches (`profile` in the launcher's
preferences), and everything in the window is about it: the checklist,
Install, Play, the folders the menu reveals, winecfg and cmd.exe. Switching is
locked while an install or a game is under way, since each is bound to the
prefix it started in, and Quit Game has to reach the one the game runs in.

## x87 translation

The client does its floating-point math on the x87 stack, which Rosetta 2
translates slowly. Wine's loader, patched for it, re-execs the 32-bit client
under a hook that takes over that translation, and the app carries two:

- **x87sidecar**, the default. Wine hands it the process's task port itself,
  so it needs no privilege and macOS never asks for anything.
- **rosettax87_jit**, chosen under **x87 Translation** in the `…` menu while
  holding ⌥. It attaches with `task_for_pid`, so macOS asks for a password to
  authorize it when the game starts.
- **None (Stock Rosetta)**, in the same submenu: no hook at all, so the client's
  x87 code is translated by Rosetta as Apple ships it — slower, but useful for
  telling a hook's bug from the game's own.

The choice is remembered and takes effect on the next launch — the game's, and
that of winecfg or cmd.exe opened from the menu. Installing always uses
x87sidecar. The launcher sets only the chosen hook's variable
(`X87_SIDECAR_PATH` or `ROSETTA_X87_PATH`) and clears the other — both, when
there is no hook — since the loader tries the sidecar first.

rosettax87_jit is two files that must sit side by side — `runtime_loader` and
the `libRuntimeRosettax87` it injects — kept in `Resources/rosettax87_jit/` and
copied from WoWSilicon's bundle, with their hashes in
`Packaging/RosettaX87JIT/rosettax87_jit-lock.json`. `build.sh` copies them into
the app without re-signing them, so the loader keeps the debugger entitlement
its own signature carries.

## Command-key game shortcuts

**Use ⌘ for Game Shortcuts** is visible in the `…` menu without holding
Option. It is on by default, and the choice is remembered between launcher
sessions. It is disabled while the launcher is installing or running the game;
changes take effect on the next **Play** or **Install/Repair**.

Wine normally maps Command to Windows Alt, but the bundled runtime's native
Mac Edit menu intercepts Command+A/C/V/X/Z and sends editing commands instead.
The toggle configures only this game's registry value:

```text
HKEY_CURRENT_USER\Software\Wine\AppDefaults\Ragexe.exe\Mac Driver
EditMenu (REG_SZ): "disabled" when on, "key" when off
```

With it on, those keys reach the game as Alt shortcuts; use Windows Control
shortcuts for text editing where the client supports them. Turning it off
explicitly restores the runtime's default Mac editing behavior for the game.
Other Windows applications, the Mac launcher, Command/Option modifier mappings,
and the signed app bundle are not changed.

The setting is applied after creating (or finding) the prefix during installation
and before each game launch, so existing installs do not need to be recreated.
Repairs and client reinstalls honor the saved choice, including **off**. On Play,
the same effective environment is used for the registry command and the game,
including an advanced `WINEPREFIX` override. A failed registry command is
reported and stops the operation instead of claiming the setting was applied.

The saved preference is `commandShortcuts` in the launcher's macOS preferences.
The Wine value lives in the chosen prefix's `user.reg`; to stop managing it
entirely, use an unmodified launcher and remove only `EditMenu` from the key
above. This feature does not add backup files, helper apps, or system services.

### Testing

```sh
swift test
swift build -c release
```

Automated tests use an injected registry runner and isolated preference domains;
they do not launch Wine, download the client, or modify a real Wine prefix.
For an end-to-end check, use a disposable install root (`RO_ROOT`), confirm the
value after Install/Repair and after Play with each toggle state, and verify
Command+A/C/V/X/Z in-game. Also check that turning the option off persists after
restarting the launcher, repairing, or reinstalling the client. Game input needs
manual verification; a successful registry write alone does not prove it.

## The wintrust patch

The client's copy-protection component calls `WinVerifyTrust` on
`C:\windows\system32\ntdll.dll`. Under Wine that file is Wine's own unsigned
reimplementation, so the call fails with
`TRUST_E_NOSIGNATURE` and the client aborts — a false positive by construction,
since Wine's DLLs can never carry a Microsoft signature.
[0014-wintrust-trust-every-file.patch](Packaging/WineRuntime/patches/0014-wintrust-trust-every-file.patch)
makes Wine's `WinVerifyTrust` return `ERROR_SUCCESS` for every file, and
`WinVerifyTrustEx` with it, since it calls through `WinVerifyTrust`.

It is one of the runtime's patches, built into `wintrust.dll` from source, so
nothing is patched after the fact: not by `build.sh`, and never by the
launcher. This Wine copies its DLLs into each prefix rather than symlinking
them, and loads the prefix's copy in preference to the runtime's, so a prefix
created from that runtime is born with it too. The launcher neither applies nor
reports it — there is nothing for it to decide.

## The Steam stub

The client expects to find Steam running, so the app carries a small stand-in
that launches the game and waits until no client is left running — every copy
of it, not only the first, so each Play lasts as long as the whole session. It
lives in
[tools/steam-stub/](tools/steam-stub/) as the C source it is built from — there
is no `.exe` checked into this repository.

`make steam-stub` cross-compiles it into `.steam-stub`, and `build.sh` copies it
from there into the bundle, the same arrangement as the Wine runtime and
`.wine-runtime`. Both folders are gitignored build products the build consumes
rather than makes: `build.sh` says what to run if either is missing instead of
producing it in the middle of an app build.

It is a 32-bit Windows GUI program, so it needs the mingw-w64 cross-compiler:

```sh
make steam-stub-toolchain   # brew install mingw-w64
```

That compiler only runs when the stub is actually out of date. `.steam-stub/steam_stub.exe`
is the one real file target in the Makefile — it is rebuilt when `steam_stub.c`
or the build script is newer and left alone otherwise, so an ordinary
`make` never invokes it. `make bundle` checks the result over the way it checks
the Wine runtime, `make clean` removes `.steam-stub`, and nothing installs a
compiler behind your back.

The build is reproducible — the same source and compiler give the same bytes, so
a rebuild that changes nothing does not churn the binary the app ships.
`STEAM_STUB` points somewhere other than `.steam-stub`, and `STEAM_STUB_CC`
names a cross-compiler other than `i686-w64-mingw32-gcc`.

## The Wine runtime

`make runtime` builds it from source into `.wine-runtime`, which must not exist
yet. It restores the runtime `artifact-lock.json` pins as the base, fetches the
Wine commit `Packaging/WineRuntime/runtime-lock.json` pins, applies the patches
beside it in order, builds, then assembles and validates the tree. It takes a
few minutes, and leaves its working trees in `.build/wine-runtime`. It needs
Apple Silicon with Rosetta 2, Xcode, and:

```sh
brew install bison mingw-w64 freetype gnutls xz
```

`make release-runtime` publishes that tree as this repository's GitHub release
`wine-runtime-r<runtimeRevision>`, tagged at the commit checked out (which must
be pushed), and pins it in `artifact-lock.json`. Committing that lock is what
points `make restore`, and the next build, at it. A new runtime gets a new
`runtimeRevision` in `runtime-lock.json` before it is built.

Everything below the launcher is x86_64, but Homebrew stopped building Intel
bottles in September 2026, so the runtime is built on Apple Silicon under
Rosetta 2: Xcode's clang compiles the host side for x86_64 against headers from
the arm64 Homebrew, and mingw-w64 compiles the Windows side as it would anywhere.
Wine loads FreeType, GnuTLS and MoltenVK by name at run time, and configure
learns those names by linking against x86_64 copies. Those copies, like the
mtld3d and library overlays assembled into the tree, come from the runtime the
lock pinned before, so each release is built on the last one; the first was
built on WoWSilicon's r15. The runtime targets macOS 14, like the app.

Wine's Mac driver titles its application menu — and the Hide and Quit items in
it — after the `CFBundleName` of the Info.plist embedded in its loader.
[0013-loader-name-the-app-rosilicon.patch](Packaging/WineRuntime/patches/0013-loader-name-the-app-rosilicon.patch)
makes that ROSilicon (`com.rosilicon.wine`), and `validate.sh` refuses a tree
without it. The process itself is still `wine` to macOS, as it always was.

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
Packaging/RosettaX87JIT/ the hashes of the bundled rosettax87_jit
tools/wine-runtime/      build, assemble, validate, package and restore the runtime
tools/steam-stub/        the Steam stub's source, and the scripts around it
.wine-runtime/           the Wine tree the app ships (gitignored, `make restore`)
.steam-stub/             the built Steam stub (gitignored, `make steam-stub`)
Resources/
  d9vk/d3d9.dll          Direct3D 9 to Vulkan, bundled into the app
  x87sidecar/            the x87 hook, bundled into the app
  rosettax87_jit/        the alternative x87 hook behind ⌥, bundled into the app
  Localizations/         en.lproj, pt-BR.lproj, es.lproj
Sources/ROSilicon/
  Paths.swift            paths, the bundled runtime, the Wine environment
  Profile.swift          the profiles: where each prefix lives, listing, naming
  Shell.swift            subprocesses with streamed output and cancellation
  Rosetta.swift          whether Rosetta 2 is installed on this Mac
  Downloader.swift       resumable ranged downloads, retries, md5
  Installer.swift        the install stages
  GameRunner.swift       the launch path
  GameKeyboardSettings.swift  the saved Command-shortcut choice and Wine setting
  LaunchOptions.swift    WINEDEBUG and the extra variables, as typed
  X87Backend.swift       the choice between the two x87 hooks
  Status.swift           what is installed right now
  LauncherModel.swift    state and actions behind the window
  ContentView.swift      the window
  LauncherApp.swift      the entry point: the window's scene and menu commands
  Strings.swift          every word the launcher shows
```

`RO_ROOT` overrides the install folder and `RO_TOOLS` the folder everything
bundled is read from — Wine included, since the runtime sits at `Wine/` under
it. Both are useful when running outside an app bundle.

## Credits

- **WoWSilicon** — [WoWSilicon/WoWSilicon](https://github.com/WoWSilicon/WoWSilicon)
  — the Wine patches and runtime tooling this one's is built with, the mtld3d
  and library overlays it carries, and the Rosetta work behind it.
- **x87sidecar** — [athei/x87sidecar](https://github.com/athei/x87sidecar) — the
  x87 hook the runtime re-execs into; the bundled binary is that project's
  release, tracked in `Packaging/X87Sidecar/x87sidecar-lock.json`. Built on
  [Lifeisawful/rosettax87_jit](https://github.com/Lifeisawful/rosettax87_jit).
- **rosettax87_jit** — [Lifeisawful/rosettax87_jit](https://github.com/Lifeisawful/rosettax87_jit)
  — the alternative x87 hook behind ⌥; the bundled binaries are WoWSilicon's,
  tracked in `Packaging/RosettaX87JIT/rosettax87_jit-lock.json`.
- **Wintrust patch** — [alexandrephz/ragnarok-no-linux](https://gitlab.com/alexandrephz/ragnarok-no-linux)
- **D9VK** — [Sikarugir-App/d9vk](https://github.com/Sikarugir-App/d9vk)

## License

ROSilicon is free software, licensed under the
[GNU General Public License v3.0](LICENSE) or, at your option, any later
version. It comes with no warranty. The components it bundles — the Wine
runtime, `x87sidecar`, `rosettax87_jit`, DXVK/D9VK — keep the licenses of their own projects,
listed under [Credits](#credits).
