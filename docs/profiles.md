# Profiles

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

