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
    static var starting: String { t("button.starting") }
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
    static var menuMetalHUD: String { t("menu.metal_hud") }
    static var menuX87Backend: String { t("menu.x87_backend") }
    static var menuX87Sidecar: String { t("menu.x87_backend.sidecar") }
    static var menuRosettaX87JIT: String { t("menu.x87_backend.rosettax87_jit") }
    static var menuX87Disabled: String { t("menu.x87_backend.disabled") }
    static var menuCommandShortcuts: String { t("menu.command_shortcuts") }
    static var commandShortcutsHelp: String { t("help.command_shortcuts") }
    static var menuFunctionKeys: String { t("menu.function_keys") }
    static var functionKeysHelp: String { t("help.function_keys") }
    static var menuDiscordPresence: String { t("menu.discord_presence") }
    static var discordPresenceHelp: String { t("help.discord_presence") }
    static var menuWineDebug: String { t("menu.wine_debug") }
    static var menuEnvironment: String { t("menu.environment") }
    static var menuWinecfg: String { t("menu.winecfg") }
    static var menuCommandPrompt: String { t("menu.command_prompt") }
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

    // MARK: - Sheets

    static var clientURLTitle: String { t("sheet.client_url.title") }
    static var clientURLExplanation: String { t("sheet.client_url.explanation") }
    static var clientURLField: String { t("sheet.client_url.field") }
    static var wineDebugTitle: String { t("sheet.wine_debug.title") }
    static var wineDebugExplanation: String { t("sheet.wine_debug.explanation") }
    static var wineDebugField: String { t("sheet.wine_debug.field") }
    static var environmentTitle: String { t("sheet.environment.title") }
    static var environmentExplanation: String { t("sheet.environment.explanation") }
    static var environmentField: String { t("sheet.environment.field") }
    static var resetToDefault: String { t("sheet.reset") }
    static var done: String { t("sheet.done") }

    // MARK: - Profiles

    static var profileDefault: String { t("profile.default") }
    static var menuProfile: String { t("menu.profile") }
    static var profileHelp: String { t("help.profile") }
    static var menuNewProfile: String { t("menu.new_profile") }
    static func menuDeleteProfile(_ name: String) -> String { t("menu.delete_profile", name) }
    static var newProfileTitle: String { t("sheet.new_profile.title") }
    static var newProfileExplanation: String { t("sheet.new_profile.explanation") }
    static var newProfileField: String { t("sheet.new_profile.field") }
    static var newProfileCreate: String { t("sheet.new_profile.create") }
    static func deleteProfileTitle(_ name: String) -> String {
        t("dialog.delete_profile.title", name)
    }
    static var deleteProfileConfirm: String { t("dialog.delete_profile.confirm") }
    static func deleteProfileMessage(_ folder: String, _ size: String) -> String {
        t("dialog.delete_profile.message", folder, size)
    }
    static func deleteProfileMessageNoSize(_ folder: String) -> String {
        t("dialog.delete_profile.message_no_size", folder)
    }
    static func stepRemovingProfile(_ name: String) -> String { t("step.removing_profile", name) }
    static func stepProfileRemoved(_ name: String) -> String { t("step.profile_removed", name) }
    static var errorProfileNameEmpty: String { t("error.profile_name_empty") }
    static var errorProfileNameInvalid: String { t("error.profile_name_invalid") }
    static func errorProfileNameTaken(_ name: String) -> String {
        t("error.profile_name_taken", name)
    }
    static var errorDefaultProfileNotDeletable: String {
        t("error.default_profile_not_deletable")
    }

    // MARK: - Checklist

    static var itemRosetta: String { t("item.rosetta") }
    static var itemWine: String { t("item.wine") }
    static var itemPrefix: String { t("item.prefix") }
    static var itemClient: String { t("item.client") }

    static func wineVersion(_ version: String) -> String { t("detail.wine_version", version) }
    static var notInstalled: String { t("detail.not_installed") }
    static var rosettaInstalled: String { t("detail.rosetta_installed") }
    static var rosettaNeedsAppleSilicon: String { t("detail.rosetta_needs_apple_silicon") }
    static var incompleteInstallAgain: String { t("detail.incomplete_install_again") }
    static var notCreated: String { t("detail.not_created") }
    static var incomplete: String { t("detail.incomplete") }
    static func clientDated(_ date: String) -> String { t("detail.client_dated", date) }

    // MARK: - Status line

    static var readyToPlay: String { t("status.ready") }
    static var notInstalledYet: String { t("status.not_installed_yet") }
    static var cancelled: String { t("status.cancelled") }
    static func transferred(_ done: String, _ total: String) -> String {
        t("status.transferred", done, total)
    }
    static func perSecond(_ amount: String) -> String { t("status.per_second", amount) }

    // MARK: - Steps

    static func stepCheckingWine(_ version: String) -> String {
        t("step.checking_wine", version)
    }
    static var stepCheckingRosetta: String { t("step.checking_rosetta") }
    static var stepCheckingSidecar: String { t("step.checking_sidecar") }
    static var stepCreatingPrefix: String { t("step.creating_prefix") }
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
    static func logRemovingOld(_ name: String) -> String {
        t("log.removing_old", name)
    }
    static func logUsingWine(_ version: String) -> String { t("log.using_wine", version) }
    static var logUnknownWineVersion: String { t("log.unknown_wine_version") }
    static var logRosettaOK: String { t("log.rosetta_ok") }
    static var logSidecarOK: String { t("log.sidecar_ok") }
    static var logSidecarUnsupported: String { t("log.sidecar_unsupported") }
    static func logPrefixExists(_ path: String) -> String { t("log.prefix_exists", path) }
    static func logCreatingPrefix(_ path: String) -> String { t("log.creating_prefix", path) }
    static var logPrefixReady: String { t("log.prefix_ready") }
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
    static var logRosettaX87JIT: String { t("log.rosettax87_jit") }
    static var logX87Disabled: String { t("log.x87_disabled") }
    static var logCommandShortcutsOn: String { t("log.command_shortcuts_on") }
    static var logCommandShortcutsOff: String { t("log.command_shortcuts_off") }
    static var logFunctionKeysStandard: String { t("log.function_keys_standard") }
    static var logFunctionKeysRestored: String { t("log.function_keys_restored") }
    static var logFunctionKeysNotRestored: String { t("log.function_keys_not_restored") }
    static var logFunctionKeysUnavailable: String { t("log.function_keys_unavailable") }
    static var logDiscordPresence: String { t("log.discord_presence") }
    static func logDiscordPresenceRefused(_ message: String) -> String {
        t("log.discord_presence_refused", message)
    }
    static func logWineDebug(_ channels: String) -> String { t("log.wine_debug", channels) }
    static func logExtraEnvironment(_ variables: String) -> String {
        t("log.extra_environment", variables)
    }
    static func logOpeningTool(_ name: String) -> String { t("log.opening_tool", name) }
    static func logToolExited(_ name: String, _ status: Int32) -> String {
        t("log.tool_exited", name, status)
    }
    static var logExitedNormally: String { t("log.exited_normally") }
    static var unknownSize: String { t("log.unknown_size") }

    // MARK: - Errors

    static var errorPrefix: String { t("error.prefix") }
    static func errorRootNotWritable(_ path: String) -> String {
        t("error.root_not_writable", path)
    }
    static var errorWineRunning: String { t("error.wine_running") }
    static func errorWineRuntimeMissing(_ path: String) -> String {
        t("error.wine_runtime_missing", path)
    }
    static func errorSidecarMissing(_ path: String) -> String { t("error.sidecar_missing", path) }
    static func errorRosettaMissing(_ command: String) -> String {
        t("error.rosetta_missing", command)
    }
    static var errorNotAppleSilicon: String { t("error.not_apple_silicon") }
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
}
