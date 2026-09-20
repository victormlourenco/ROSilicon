# x87 translation

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

