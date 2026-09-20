# Discord Rich Presence

While a game runs, the Discord app shows it as **Playing Ragnarok Online**, with
the time since the first client started. Discord cannot see that for itself: it
recognizes games by their executable, and to macOS the client is a process
called `wine`. So the launcher tells it, over the local socket the Discord app
opens for programs on the same Mac (`discord-ipc-0` in `$TMPDIR`) — the one
every game with Rich Presence talks to. The launcher sends nothing over the
network, and the activity carries the game and the time played, not the
profile's name.

It uses Discord's own application for the game, `498990766643740692` — the one
Discord detects `Ragexe.exe` as on Windows — so the name and icon are the ones
Discord already has for Ragnarok Online, and there is nothing to register.

**Show Game Activity in Discord** is in the `…` menu without holding Option. It
is on by default, remembered between launcher sessions (`discordPresence` in
the launcher's preferences), and takes effect at once, a game already running
included. Who sees the activity is up to Discord's own Activity Privacy
settings.

Discord need not be open first. The launcher looks for it every 15 seconds while
the game runs, and finds it again if it is quit and reopened. It says nothing in
the log while Discord is away; it logs once when the activity is shown, and once
if Discord refuses it, after which it stops asking until the next game.
Presence ends when the last client closes: closing the connection is what
clears it, so a launcher that quits takes it down too.

