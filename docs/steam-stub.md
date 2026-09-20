# The Steam stub

The client expects to find Steam running, so the app carries a small stand-in
that launches the game and waits until no client is left running — every copy
of it, not only the first, so each Play lasts as long as the whole session. It
lives in
[tools/steam-stub/](../tools/steam-stub/) as the C source it is built from — there
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

