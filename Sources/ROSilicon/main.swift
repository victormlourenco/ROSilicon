import Foundation

// A one-flag command line in front of the window, so `build.sh` can patch the
// Wine runtime it bundles with the very code the launcher runs at install time
// — one implementation of the PE surgery, not two.
//
//   ROSilicon --patch-wintrust FILE...
//
// Anything else falls through to the app.
let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--patch-wintrust" {
    let files = arguments.dropFirst()
    guard !files.isEmpty else {
        FileHandle.standardError.write(
            Data("usage: ROSilicon --patch-wintrust FILE...\n".utf8))
        exit(2)
    }

    var failed = false
    for file in files {
        let url = URL(filePath: file).standardizedFileURL
        do {
            let changed = try WintrustPatch.patch(url)
            print("    \(changed ? "patched" : "already patched") \(url.lastPathComponent)"
                + " (\(url.deletingLastPathComponent().lastPathComponent))")
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            failed = true
        }
    }
    exit(failed ? 1 : 0)
}

ROSiliconApp.main()
