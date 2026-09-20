# ROSilicon technical documentation

The [README](../README.md) is for playing the game. These pages are for working
on the launcher: how it is built, what it ships, and why each piece is there.

## Working on it

- [Building ROSilicon](building.md) — the `make` targets, what each needs, and
  how the tests are run.
- [Repository layout](layout.md) — every folder and source file, and what lives
  in it.
- [Languages](languages.md) — where the strings live and how to add a language.

## How it behaves

- [How the app installs and runs the game](how-it-works.md) — the install
  folder, the three install stages, and what **Play** does.
- [Profiles](profiles.md) — one Wine prefix per profile, and what switching
  touches.
- [Keyboard](keyboard.md) — ⌘ shortcuts inside the client, and borrowing the
  Mac's F1–F12 mode while the game runs.
- [Discord Rich Presence](discord.md) — how the activity reaches Discord over
  its local socket.
- [x87 translation](x87-translation.md) — the two x87 hooks, and what each costs.

## What the app ships

- [The Wine runtime](wine-runtime.md) — how the bundled Wine is built, pinned
  and released, including the wintrust patch the client needs.
- [DXVK](dxvk.md) — Direct3D 9 on Metal, the pinned branch and our patches.
- [The Steam stub](steam-stub.md) — the stand-in the client expects to find
  running.
