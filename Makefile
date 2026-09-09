# A thin wrapper over build.sh, which does the real work. The script cds to its
# own folder and swift build already tracks what needs recompiling, so every
# target here is phony: make chooses nothing, it only names the builds.
#
# APP_OUT builds somewhere other than this folder, the same as it does for
# build.sh:  make APP_OUT=/tmp/ro dmg
#
# WINE_RUNTIME points at the Wine tree the app ships; build.sh copies it into
# ROSilicon.app/Contents/Resources/Wine, and the app installs from there.

APP_NAME := ROSilicon
OUT      := $(or $(APP_OUT),.)
WINE_RUNTIME ?= $(CURDIR)/.wine-runtime

# build.sh reads these out of the environment; unset and empty both mean "here".
export APP_OUT
export WINE_RUNTIME

.DEFAULT_GOAL := app
.PHONY: app app-no-wine dmg run test clean help validate_wine_runtime \
        package_wine_runtime validate_steam_stub \
        update-mtld3d update-x87sidecar restore bundle \
        steam-stub steam-stub-toolchain

# Note this is not what ./build.sh on its own does — that packs a .dmg too.
# Laying the disk image out drives the Finder and takes a while, so the bare
# .app is the default for the edit-build-run loop.
app:
	./build.sh --no-dmg

# The same, minus the Wine runtime: seconds quicker and enough for work on the
# UI, but the app it builds cannot install.
app-no-wine:
	./build.sh --no-dmg --no-wine

# The .app and the .dmg to hand to someone else, named after VERSION.
dmg:
	./build.sh

run: app
	open "$(OUT)/$(APP_NAME).app"

# The suite is swift-testing, so it builds the package on its own and never
# needs the .app. FILTER narrows it down to the tests whose names match:
#     make FILTER=Downloader test
test:
	swift test $(if $(FILTER),--filter "$(FILTER)",)

# Only build products, every one of them gitignored.
clean:
	rm -rf .build "$(OUT)/$(APP_NAME).app" "$(OUT)"/$(APP_NAME)-*.dmg

help:
	@echo "make             build $(APP_NAME).app — the fast one"
	@echo "make dmg         build the .app and the .dmg"
	@echo "make run         build the .app and open it"
	@echo "make test        run the test suite"
	@echo "make bundle      check the Wine runtime, then build the .app and the .dmg"
	@echo "make restore     fetch the pinned Wine runtime into .wine-runtime"
	@echo "make steam-stub  check the Steam stub still compiles"
	@echo "make steam-stub-toolchain  install the Windows cross-compiler"
	@echo "make app-no-wine build without the Wine runtime — UI work only"
	@echo "make clean       remove the build products"
	@echo
	@echo "APP_OUT=<dir>      builds somewhere other than this folder."
	@echo "WINE_RUNTIME=<dir> ships a Wine tree other than .wine-runtime."
	@echo "FILTER=<name>      runs only the matching tests."

validate_wine_runtime:
	@test -d "$(WINE_RUNTIME)" || (echo "Wine runtime not found at $(WINE_RUNTIME)" >&2; exit 1)
	@tools/wine-runtime/validate.sh --runtime "$(WINE_RUNTIME)"

package_wine_runtime:
	@tools/wine-runtime/package.sh --runtime "$(WINE_RUNTIME)"

update-mtld3d:
	@tools/wine-runtime/update-mtld3d.sh $(if $(TAG),--tag $(TAG),)

restore:
	@tools/wine-runtime/restore.sh --runtime "$(WINE_RUNTIME)"

update-x87sidecar:
	@tools/wine-runtime/update-x87sidecar.sh $(if $(TAG),--tag $(TAG),)

# steam_stub.exe, cross-compiled from tools/steam-stub/steam_stub.c. build.sh
# compiles it straight into the app, so this target is only for checking that
# the stub still builds — it writes into .build, and nothing reads it there.
steam-stub:
	@tools/steam-stub/build.sh

# Installs the cross-compiler with Homebrew. Separate from the build, so a build
# reports a missing toolchain rather than installing one behind your back.
steam-stub-toolchain:
	@tools/steam-stub/build.sh --install --check

validate_steam_stub:
	@tools/steam-stub/build.sh --check

# The whole thing to hand to someone else: the runtime checked against the lock,
# then the .app and the .dmg holding it. build.sh compiles the Steam stub into
# the bundle itself, so there is nothing to do for it here.
bundle: validate_wine_runtime dmg
