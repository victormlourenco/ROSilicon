# A thin wrapper over build.sh, which does the real work. The script cds to its
# own folder and swift build already tracks what needs recompiling, so nearly
# every target here is phony: make chooses nothing, it only names the builds.
# The Steam stub is the exception — see the rule near the bottom.
#
# APP_OUT builds somewhere other than this folder, the same as it does for
# build.sh:  make APP_OUT=/tmp/ro dmg
#
# WINE_RUNTIME points at the Wine tree the app ships; build.sh copies it into
# ROSilicon.app/Contents/Resources/Wine, and the app installs from there.
#
# STEAM_STUB points at the folder holding the built steam_stub.exe, which
# build.sh copies into ROSilicon.app/Contents/Resources.

APP_NAME := ROSilicon
OUT      := $(or $(APP_OUT),.)
WINE_RUNTIME ?= $(CURDIR)/.wine-runtime
STEAM_STUB   ?= $(CURDIR)/.steam-stub

STEAM_STUB_EXE := $(STEAM_STUB)/steam_stub.exe
STEAM_STUB_SRC := tools/steam-stub/steam_stub.c tools/steam-stub/build.sh

# build.sh reads these out of the environment; unset and empty both mean "here".
export APP_OUT WINE_RUNTIME STEAM_STUB

.DEFAULT_GOAL := app
.PHONY: app app-no-wine dmg run test clean help validate_wine_runtime \
        validate_steam_stub update-mtld3d update-x87sidecar restore runtime \
        release-runtime bundle steam-stub steam-stub-toolchain

# Note this is not what ./build.sh on its own does — that packs a .dmg too.
# Laying the disk image out drives the Finder and takes a while, so the bare
# .app is the default for the edit-build-run loop.
app: $(STEAM_STUB_EXE)
	./build.sh --no-dmg

# The same, minus the Wine runtime: seconds quicker and enough for work on the
# UI, but the app it builds cannot install.
app-no-wine: $(STEAM_STUB_EXE)
	./build.sh --no-dmg --no-wine

# The .app and the .dmg to hand to someone else, named after VERSION.
dmg: $(STEAM_STUB_EXE)
	./build.sh

run: app
	open "$(OUT)/$(APP_NAME).app"

# The suite is swift-testing, so it builds the package on its own and never
# needs the .app. FILTER narrows it down to the tests whose names match:
#     make FILTER=Downloader test
test:
	swift test $(if $(FILTER),--filter "$(FILTER)",)

# The build products, every one of them gitignored — the Wine runtime and the
# Steam stub included, so `make runtime` can start over. Getting the runtime
# back takes `make restore` or `make runtime`, both slow. Only this folder's
# copies go: a WINE_RUNTIME or STEAM_STUB pointed elsewhere is left alone.
clean:
	rm -rf .build .wine-runtime .steam-stub "$(OUT)/$(APP_NAME).app" "$(OUT)"/$(APP_NAME)-*.dmg

help:
	@echo "make             build $(APP_NAME).app — the fast one"
	@echo "make dmg         build the .app and the .dmg"
	@echo "make run         build the .app and open it"
	@echo "make test        run the test suite"
	@echo "make bundle      check the Wine runtime, then build the .app and the .dmg"
	@echo "make restore     fetch the pinned Wine runtime into .wine-runtime"
	@echo "make runtime     build the Wine runtime from source into .wine-runtime"
	@echo "make release-runtime  publish .wine-runtime as a GitHub release"
	@echo "make steam-stub  build the Steam stub into .steam-stub"
	@echo "make steam-stub-toolchain  install the Windows cross-compiler"
	@echo "make app-no-wine build without the Wine runtime — UI work only"
	@echo "make clean       remove the build products"
	@echo
	@echo "APP_OUT=<dir>      builds somewhere other than this folder."
	@echo "WINE_RUNTIME=<dir> ships a Wine tree other than .wine-runtime."
	@echo "STEAM_STUB=<dir>   ships a Steam stub other than .steam-stub."
	@echo "FILTER=<name>      runs only the matching tests."

validate_wine_runtime:
	@test -d "$(WINE_RUNTIME)" || (echo "Wine runtime not found at $(WINE_RUNTIME)" >&2; exit 1)
	@tools/wine-runtime/validate.sh --runtime "$(WINE_RUNTIME)"

update-mtld3d:
	@tools/wine-runtime/update-mtld3d.sh $(if $(TAG),--tag $(TAG),)

restore:
	@tools/wine-runtime/restore.sh --runtime "$(WINE_RUNTIME)"

# Builds the Wine runtime from source into WINE_RUNTIME, which must not exist
# yet: several minutes on Apple Silicon, under Rosetta 2. See the README.
runtime:
	@tools/wine-runtime/build-runtime.sh --output "$(WINE_RUNTIME)"

# Publishes WINE_RUNTIME as the GitHub release runtime-lock.json names, and
# pins it in artifact-lock.json, which is then yours to commit.
release-runtime:
	@tools/wine-runtime/release.sh --runtime "$(WINE_RUNTIME)"

update-x87sidecar:
	@tools/wine-runtime/update-x87sidecar.sh $(if $(TAG),--tag $(TAG),)

# The one real file target in here. steam_stub.exe is cross-compiled into
# .steam-stub and build.sh copies it from there, so an ordinary build never runs
# the Windows compiler: make rebuilds it when its source is newer and leaves it
# alone otherwise.
$(STEAM_STUB_EXE): $(STEAM_STUB_SRC)
	@tools/steam-stub/build.sh --output "$@"

steam-stub: $(STEAM_STUB_EXE)

# Installs the cross-compiler with Homebrew, then builds. Separate from the
# build rule, so a build reports a missing toolchain rather than installing one
# behind your back.
steam-stub-toolchain:
	@tools/steam-stub/build.sh --install --output "$(STEAM_STUB_EXE)"

validate_steam_stub:
	@tools/steam-stub/validate.sh --stub "$(STEAM_STUB)"

# The whole thing to hand to someone else: the runtime checked against the lock,
# the stub built and checked over, then the .app and the .dmg holding it. The
# stub is named before the check that reads it, so a first bundle builds it
# rather than failing on its absence.
bundle: validate_wine_runtime $(STEAM_STUB_EXE) validate_steam_stub dmg
