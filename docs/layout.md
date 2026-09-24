# Repository layout

```
VERSION                  the version the build stamps into the app and the .dmg
Package.swift            SwiftPM manifest (macOS 14+, Swift 6)
build.sh                 builds, assembles and signs the .app, packs the .dmg
makeicon.swift           draws AppIcon.icns, no asset files needed
Makefile                 names the builds; build.sh does the work
Packaging/WineRuntime/   the runtime and artifact locks, and the Wine patches
Packaging/RosettaX87JIT/ the hashes of the bundled rosettax87_jit
Packaging/D9VK/          the DXVK source lock, and the patches applied to it
Packaging/KosmicKrisp/   the Mesa and Vulkan loader source lock
tools/wine-runtime/      build, assemble, validate, package and restore the runtime
tools/steam-stub/        the Steam stub's source, and the scripts around it
tools/d9vk/              build and validate DXVK's d3d9.dll
tools/kosmickrisp/       build the x86_64 Vulkan loader and KosmicKrisp
tools/publish-wiki.sh    copies wiki/ to the GitHub wiki
wiki/                    the wiki's pages, as files; see wiki/README.md
.wine-runtime/           the Wine tree the app ships (gitignored, `make restore`)
.steam-stub/             the built Steam stub (gitignored, `make steam-stub`)
.d9vk/                   the built d3d9.dll (gitignored, `make d9vk`)
.kosmickrisp/            the built loader and driver (gitignored, `make kosmickrisp`)
Resources/
  d9vk/d3d9.dll          Direct3D 9 to Vulkan, the fallback when .d9vk is empty
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
  FunctionKeys.swift     the Mac's F1–F12 mode, borrowed while the game runs
  LaunchOptions.swift    WINEDEBUG and the extra variables, as typed
  X87Backend.swift       the choice between the two x87 hooks
  VulkanDriver.swift     KosmicKrisp or MoltenVK, by macOS version
  DiscordPresence.swift  the game's activity in the Discord app, over its local socket
  Status.swift           what is installed right now
  LauncherModel.swift    state and actions behind the window
  ContentView.swift      the window
  LauncherApp.swift      the entry point: the window's scene and menu commands
  Strings.swift          every word the launcher shows
```

`RO_ROOT` overrides the install folder and `RO_TOOLS` the folder everything
bundled is read from — Wine included, since the runtime sits at `Wine/` under
it. Both are useful when running outside an app bundle.

