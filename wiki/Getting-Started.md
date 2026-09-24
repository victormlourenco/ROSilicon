# Getting Started

🇺🇸 English · [🇧🇷 Português](Primeiros-Passos) · [🇪🇸 Español](Primeros-Pasos)

ROSilicon installs Ragnarok Online LATAM on your Mac and runs it. You do not
need Windows, Boot Camp, or any knowledge of Wine — the app carries everything
except the game client, which it downloads for you.

<p align="center">
  <img src="https://raw.githubusercontent.com/wiki/victormlourenco/ROSilicon/images/launcher-en.png" width="620" alt="The ROSilicon window, ready to play">
</p>

## Before you start

- A Mac with **Apple Silicon** — M1, M2, M3, M4 or newer. Intel Macs are not
  supported. (Apple menu › **About This Mac**: the Chip line should say *Apple*.)
- **macOS 14 Sonoma** or newer.
- **Rosetta 2.** If you have never installed it, open Terminal and run
  `softwareupdate --install-rosetta`. The launcher also checks, and tells you
  within a second if it is missing.
- About **12 GB of free space**. The game client alone is about 4.8 GB to
  download.

## 1. Download

Go to the [releases page](https://github.com/victormlourenco/ROSilicon/releases/latest)
and download **ROSilicon-&lt;version&gt;.dmg**.

## 2. Install the app

Open the downloaded disk image and drag **ROSilicon** onto the **Applications**
folder shown beside it. Then eject the disk image.

## 3. Open it the first time

macOS will refuse to open it the first time, saying it cannot verify the
developer. That is expected: the app is not signed with a paid Apple developer
certificate, so your Mac has no way to check who made it.

1. Open **System Settings › Privacy & Security**.
2. Scroll down to the message about ROSilicon and click **Open Anyway**.
3. Open the app again and confirm.

You only do this once. On older versions of macOS, right-clicking the app and
choosing **Open** is enough.

> If **Open Anyway** never appears, open Terminal and run
> `xattr -dr com.apple.quarantine /Applications/ROSilicon.app`, then open the app.

## 4. Install the game

Press **Install**. The launcher works through a short checklist and shows you
where it is:

| | |
|---|---|
| **Rosetta 2** | Checked first, so a Mac without it is told in a second — not after several gigabytes. |
| **Wine runtime** | Already inside the app. Nothing to download. |
| **Wine prefix** | The Windows environment the game runs in, created for you. |
| **Game client** | About 4.8 GB, downloaded from the official server, verified and unpacked. |

The download is the long part. If it is interrupted — you close the launcher,
the Wi-Fi drops — press **Install** again and it picks up where it left off.
Press **Log** at the bottom of the window to watch it in detail.

## 5. Play

Press **Play**. The game starts, and from here on that is the whole routine:
open ROSilicon, press **Play**.

- Press **Play** again while the game is running to open a **second client** in
  the same installation — useful for a vending character.
- **Quit Game** closes every client at once.
- **Repair** re-checks the installation and fixes what is missing.

## Settings worth turning on

They are in the **`…` menu** in the top-right corner of the window, and each is
remembered.

- **Use ⌘ for Game Shortcuts** — on by default. Sends ⌘A/C/V/X/Z to the game as
  the Alt shortcuts the client expects, instead of Mac editing commands. Use
  Control for copy and paste in chat.
- **Use F1–F12 as Function Keys in Game** — **off by default, and most people
  want it on.** Without it, F1–F12 change the brightness and volume instead of
  using your hotkey bars. With it on, the top row sends F1–F12 for as long as a
  client is open, and goes back to normal the moment you close the game. Hold
  `fn` for brightness and volume in the meantime.
- **Show Game Activity in Discord** — on by default. Friends see you
  **Playing Ragnarok Online**, and for how long.

## If something goes wrong

| Problem | What to do |
|---|---|
| "ROSilicon cannot be opened" or "is damaged" | That is the missing signature, not a broken download — see step 3. |
| It stops immediately, asking for Rosetta | Run `softwareupdate --install-rosetta` in Terminal, then press **Install** again. |
| The download stalls or fails | Press **Install** again. It resumes and verifies what is already there. |
| F1–F12 change the brightness in game | Turn on **Use F1–F12 as Function Keys in Game** in the `…` menu. |
| The game is slow, crashes, or will not start | Hold **⌥ Option** while the `…` menu is open, set **x87 Translation** to **None (Stock Rosetta)** and try again. It is slower, but it separates a bug in the speed-up from a bug in the game. |
| The screen is black, or something is drawn wrong | Hold **⌥ Option** while the `…` menu is open and set **Vulkan Driver** to **MoltenVK**, the driver the launcher used before macOS 26. It takes effect the next time you press **Play**. |

Still stuck? Hold **⌥ Option** in the `…` menu, choose **Copy Log**, and
[open an issue](https://github.com/victormlourenco/ROSilicon/issues) with it
pasted in. The log is what makes a problem fixable.

## Removing it

**Clear Installation Folder…** in the `…` menu moves everything the launcher
installed to the Trash, after asking. Then drag ROSilicon from Applications to
the Trash. Nothing else is left anywhere on your Mac.

---

Updating is just replacing ROSilicon in Applications with a newer one — your
game, profiles and settings stay where they are.
