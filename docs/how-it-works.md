# How the app installs and runs the game

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
   [wintrust patch](wine-runtime.md#the-wintrust-patch) from the runtime, so there is no
   patching stage.
3. **The game client** — reads size and MD5 from the server's headers,
   downloads with resume, verifies, extracts.

**Play** links DXVK and the Steam stub into the prefix and starts the client
through `steam.exe`, which is what the client expects to find running. DXVK is
linked into the prefix's `windows/syswow64`, not beside `Ragexe.exe`, so
reinstalling the client cannot drop it; a link an older version left in the
game folder is cleared, since that folder is searched first.

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

