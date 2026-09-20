# Keyboard

Two settings the launcher manages for the game: what ⌘ does inside the client,
and what the Mac's top row sends while the client is open.

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

## Function keys

The client reads F1–F12 as its hotkey bars, but a Mac left as it comes sends
brightness, volume and the rest from that row instead — so every skill key does
something other than the skill. Flipping the Mac's own setting works, and it
stays flipped: the media keys are then gone from every other app until it is
flipped back.

**Use F1–F12 as Function Keys in Game** is in the `…` menu without holding
Option. It borrows that setting instead: the top row sends F1–F12 for as long
as a client is open, and goes back to whatever it was the moment the last one
closes. Hold `fn` for brightness and volume while the game runs. It is **off**
by default — the setting is one for the whole Mac, not just the game, so it is
not one to take without being asked — and the choice is remembered between
launcher sessions (`functionKeys` in the launcher's preferences). Turning it on
or off mid-game lands right away.

The setting is `IOHIDSystem`'s `HIDFKeyMode` parameter, reached the way
[Fluor](https://github.com/Pyroh/Fluor) reaches it — its `FKeyManager`, in turn
derived from `fntoggle`. Neither reading nor writing it needs any privilege:
the parameter connection is one macOS hands to whoever asks, which is how
System Settings' own checkbox gets there. Nothing is installed for this — no
helper, no login item, no accessibility or input-monitoring permission.

What the launcher borrows it remembers, and it never borrows what it cannot
give back:

- A Mac already on standard function keys is left alone, and nothing is put
  back afterwards — it was never changed.
- A mode that cannot be read, or that is not one of the two the launcher knows,
  is not touched at all: a value it has no case for is one it cannot promise to
  restore.
- Two clients at once share one borrow. The mode restored is the one from
  before the first of them, and the last to close is what restores it.
- Quitting the launcher mid-game restores it on the way out, synchronously,
  before the process goes.

The write is live only, which is the floor under all of that: macOS keeps the
reader's own choice in `com.apple.keyboard.fnState`, and setting the HID
parameter does not touch it. A launcher killed outright, with no chance to put
anything back, still loses to the next login — and **System Settings › Keyboard**
puts it right at any time.

## Verifying by hand

For an end-to-end check of the ⌘ setting, use a disposable install root
(`RO_ROOT`), confirm the registry value after Install/Repair and after Play with
each toggle state, and verify Command+A/C/V/X/Z in-game. Also check that turning
the option off persists after restarting the launcher, repairing, or reinstalling
the client. Game input needs manual verification; a successful registry write
alone does not prove it.
