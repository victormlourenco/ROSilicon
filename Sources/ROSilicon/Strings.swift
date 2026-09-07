import Foundation

/// Every word the launcher shows, in one place.
///
/// The translations live in `Resources/Localizations/<lang>.lproj/Localizable.strings`,
/// which `build.sh` copies into the app bundle. macOS picks the one matching the
/// reader's language and falls back to English for anything missing, so a new
/// key works everywhere the moment it is added to `en.lproj`.
enum Strings {
    private static func t(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    private static func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: Bundle.main.localizedString(forKey: key, value: key, table: nil),
               locale: .current, arguments: arguments)
    }

    // MARK: - Window and buttons

    static var appTitle: String { t("app.title") }
    static var play: String { t("button.play") }
    static var install: String { t("button.install") }
    static var repair: String { t("button.repair") }
    static var cancel: String { t("button.cancel") }
    static var quitGame: String { t("button.quit_game") }
    static var log: String { t("button.log") }
    static var installOrRepairCommand: String { t("command.install_or_repair") }

    // MARK: - Menu

    static var menuMore: String { t("menu.more") }
    static var menuShowInstallFolder: String { t("menu.show_install_folder") }
    static var menuShowGameFolder: String { t("menu.show_game_folder") }
    static var menuReinstallClient: String { t("menu.reinstall_client") }
    static var menuClientURL: String { t("menu.client_url") }
    static var menuReapplyPatch: String { t("menu.reapply_patch") }
    static var menuRestoreWintrust: String { t("menu.restore_wintrust") }
    static var menuMetalHUD: String { t("menu.metal_hud") }
    static var menuCopyLog: String { t("menu.copy_log") }
    static var menuClearInstall: String { t("menu.clear_install") }

    // MARK: - Dialogs

    static var reinstallTitle: String { t("dialog.reinstall.title") }
    static var reinstallConfirm: String { t("dialog.reinstall.confirm") }
    static var reinstallMessage: String { t("dialog.reinstall.message") }
    static var quitTitle: String { t("dialog.quit.title") }
    static var quitConfirm: String { t("dialog.quit.confirm") }
    static var quitKeepPlaying: String { t("dialog.quit.keep_playing") }
    static var quitMessage: String { t("dialog.quit.message") }
    static var clearTitle: String { t("dialog.clear.title") }
    static var clearConfirm: String { t("dialog.clear.confirm") }
    static func clearMessage(_ folder: String, _ size: String) -> String {
        t("dialog.clear.message", folder, size)
    }
    static func clearMessageNoSize(_ folder: String) -> String {
        t("dialog.clear.message_no_size", folder)
    }

    // MARK: - Client URL sheet

    static var clientURLTitle: String { t("sheet.client_url.title") }
    static var clientURLExplanation: String { t("sheet.client_url.explanation") }
    static var clientURLField: String { t("sheet.client_url.field") }
    static var clientURLReset: String { t("sheet.client_url.reset") }
    static var done: String { t("sheet.done") }

    // MARK: - Checklist

    static var itemWine: String { t("item.wine") }
    static var itemPrefix: String { t("item.prefix") }
    static var itemPatch: String { t("item.patch") }
    static var itemClient: String { t("item.client") }

    static func wineVersion(_ version: String) -> String { t("detail.wine_version", version) }
    static func wineOutdated(_ installed: String, _ available: String) -> String {
        t("detail.wine_outdated", installed, available)
    }
    static var notInstalled: String { t("detail.not_installed") }
    static var incompleteInstallAgain: String { t("detail.incomplete_install_again") }
    static var notCreated: String { t("detail.not_created") }
    static var incomplete: String { t("detail.incomplete") }
    static var noWintrustYet: String { t("detail.no_wintrust_yet") }
    static func wintrustPatched(_ count: Int) -> String { t("detail.wintrust_patched", count) }
    static var wintrustNotPatched: String { t("detail.wintrust_not_patched") }
    static func clientDated(_ date: String) -> String { t("detail.client_dated", date) }

    // MARK: - Status line

    static var readyToPlay: String { t("status.ready") }
    static var playableUnpatched: String { t("status.playable_unpatched") }
    static var notInstalledYet: String { t("status.not_installed_yet") }
    static var cancelled: String { t("status.cancelled") }
    static func transferred(_ done: String, _ total: String) -> String {
        t("status.transferred", done, total)
    }
    static func perSecond(_ amount: String) -> String { t("status.per_second", amount) }

    // MARK: - Steps

    static var stepTools: String { t("step.tools") }
    static func stepDownloadingWine(_ version: String) -> String {
        t("step.downloading_wine", version)
    }
    static func stepInstallingWine(_ version: String) -> String {
        t("step.installing_wine", version)
    }
    static var stepCheckingSidecar: String { t("step.checking_sidecar") }
    static var stepCreatingPrefix: String { t("step.creating_prefix") }
    static var stepPatching: String { t("step.patching") }
    static var stepRestoring: String { t("step.restoring") }
    static var stepCheckingDownload: String { t("step.checking_download") }
    static var stepDownloadingClient: String { t("step.downloading_client") }
    static var stepVerifying: String { t("step.verifying") }
    static var stepExtracting: String { t("step.extracting") }
    static func stepExtractingCount(_ files: Int) -> String { t("step.extracting_count", files) }
    static var stepRunning: String { t("step.running") }
    static var stepRemoving: String { t("step.removing") }
    static var stepRemoved: String { t("step.removed") }
    static var stepNothingToRemove: String { t("step.nothing_to_remove") }

    // MARK: - Log

    static func logInstallingInto(_ path: String) -> String { t("log.installing_into", path) }
    static var logReady: String { t("log.ready") }
    static var logToolsInPlace: String { t("log.tools_in_place") }
    static func logToolsCopied(_ files: String, _ folder: String) -> String {
        t("log.tools_copied", files, folder)
    }
    static var logAnd: String { t("log.and") }
    static func logWineInstalled(_ version: String) -> String { t("log.wine_installed", version) }
    static func logWineReplacing(_ old: String, _ new: String) -> String {
        t("log.wine_replacing", old, new)
    }
    static func logDownloading(_ name: String, _ size: String) -> String {
        t("log.downloading", name, size)
    }
    static func logMounting(_ name: String) -> String { t("log.mounting", name) }
    static func logCopyingApp(_ destination: String) -> String { t("log.copying_app", destination) }
    static func logUsingWine(_ version: String) -> String { t("log.using_wine", version) }
    static var logUnknownWineVersion: String { t("log.unknown_wine_version") }
    static var logSidecarOK: String { t("log.sidecar_ok") }
    static var logSidecarUnsupported: String { t("log.sidecar_unsupported") }
    static func logPrefixExists(_ path: String) -> String { t("log.prefix_exists", path) }
    static func logCreatingPrefix(_ path: String) -> String { t("log.creating_prefix", path) }
    static var logPrefixReady: String { t("log.prefix_ready") }
    static var logPatching: String { t("log.patching") }
    static func logClientInstalled(_ path: String) -> String { t("log.client_installed", path) }
    static func logQuerying(_ url: String) -> String { t("log.querying", url) }
    static func logDownloadingClient(_ size: String) -> String { t("log.downloading_client", size) }
    static var logVerifying: String { t("log.verifying") }
    static var logMD5OK: String { t("log.md5_ok") }
    static func logExtractingTo(_ path: String) -> String { t("log.extracting_to", path) }
    static func logExtracted(_ files: Int) -> String { t("log.extracted", files) }
    static func logRemovingFolder(_ name: String) -> String { t("log.removing_folder", name) }
    static func logRetrying(_ reason: String, _ attempt: Int) -> String {
        t("log.retrying", reason, attempt)
    }
    static func logNothingToRemove(_ path: String) -> String { t("log.nothing_to_remove", path) }
    static func logMovingToTrash(_ path: String) -> String { t("log.moving_to_trash", path) }
    static func logInTrash(_ path: String) -> String { t("log.in_trash", path) }
    static var logRemoved: String { t("log.removed") }
    static var logLaunching: String { t("log.launching") }
    static var logMetalHUD: String { t("log.metal_hud") }
    static var logExitedNormally: String { t("log.exited_normally") }
    static var unknownSize: String { t("log.unknown_size") }

    // MARK: - The wintrust patch

    static func patchAlreadyDone(_ file: String) -> String { t("patch.already_done", file) }
    static func patchDone(_ machine: String, _ file: String, _ exports: String) -> String {
        t("patch.done", machine, file, exports)
    }
    static func patchRestored(_ file: String) -> String { t("patch.restored", file) }
    static func patchNoBackup(_ file: String) -> String { t("patch.no_backup", file) }

    // MARK: - Errors

    static var errorPrefix: String { t("error.prefix") }
    static func errorRootNotWritable(_ path: String) -> String {
        t("error.root_not_writable", path)
    }
    static var errorWineRunning: String { t("error.wine_running") }
    static func errorMissingInDMG(_ name: String) -> String { t("error.missing_in_dmg", name) }
    static func errorSidecarMissing(_ path: String) -> String { t("error.sidecar_missing", path) }
    static func errorBundledToolMissing(_ name: String, _ folder: String) -> String {
        t("error.bundled_tool_missing", name, folder)
    }
    static func errorMissingWine(_ path: String) -> String { t("error.missing_wine", path) }
    static func errorMissingFile(_ name: String, _ path: String) -> String {
        t("error.missing_file", name, path)
    }
    static func errorGameNotInstalled(_ path: String) -> String {
        t("error.game_not_installed", path)
    }
    static func errorGameExited(_ status: Int32) -> String { t("error.game_exited", status) }
    static func errorUnreachable(_ host: String) -> String { t("error.unreachable", host) }
    static func errorHTTPStatus(_ code: Int) -> String { t("error.http_status", code) }
    static func errorIncomplete(_ got: String, _ expected: String) -> String {
        t("error.incomplete", got, expected)
    }
    static func errorChecksum(_ expected: String, _ got: String) -> String {
        t("error.checksum", expected, got)
    }
    static func errorProcessFailed(_ command: String, _ status: Int32) -> String {
        t("error.process_failed", command, status)
    }
    static func errorProcessFailedDetail(_ command: String, _ status: Int32, _ output: String) -> String {
        t("error.process_failed_detail", command, status, output)
    }
    static func errorTruncatedPE(_ path: String) -> String { t("error.truncated_pe", path) }
}
