# The Wine runtime

The app ships a Wine of its own: [WineAndAqua](https://github.com/WineAndAqua/wine)'s
macOS Wine, at the commit `Packaging/WineRuntime/runtime-lock.json` pins, with
the patches beside that lock — mostly
[WoWSilicon](https://github.com/WoWSilicon/WoWSilicon)'s — built in.

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
library overlays assembled into the tree, come from the runtime the lock pinned
before, so each release is built on the last one; the first was built on
WoWSilicon's r15. The runtime targets macOS 14, like the app.

Wine's Mac driver titles its application menu — and the Hide and Quit items in
it — after the `CFBundleName` of the Info.plist embedded in its loader.
[0013-loader-name-the-app-rosilicon.patch](../Packaging/WineRuntime/patches/0013-loader-name-the-app-rosilicon.patch)
makes that ROSilicon (`com.rosilicon.wine`), and `validate.sh` refuses a tree
without it. The process itself is still `wine` to macOS, as it always was.

## The wintrust patch

The client's copy-protection component calls `WinVerifyTrust` on
`C:\windows\system32\ntdll.dll`. Under Wine that file is Wine's own unsigned
reimplementation, so the call fails with
`TRUST_E_NOSIGNATURE` and the client aborts — a false positive by construction,
since Wine's DLLs can never carry a Microsoft signature.
[0014-wintrust-trust-every-file.patch](../Packaging/WineRuntime/patches/0014-wintrust-trust-every-file.patch)
makes Wine's `WinVerifyTrust` return `ERROR_SUCCESS` for every file, and
`WinVerifyTrustEx` with it, since it calls through `WinVerifyTrust`.

It is one of the runtime's patches, built into `wintrust.dll` from source, so
nothing is patched after the fact: not by `build.sh`, and never by the
launcher. This Wine copies its DLLs into each prefix rather than symlinking
them, and loads the prefix's copy in preference to the runtime's, so a prefix
created from that runtime is born with it too. The launcher neither applies nor
reports it — there is nothing for it to decide.

