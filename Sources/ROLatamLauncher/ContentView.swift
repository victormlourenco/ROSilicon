import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: LauncherModel
    @State private var showLog = false
    @State private var confirmReinstall = false
    @State private var confirmQuit = false
    @State private var confirmClear = false
    @State private var editingClientURL = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            checklist
            Spacer(minLength: 12)
            controls

            Divider()
            logSection
        }
        .background(.background)
        .confirmationDialog(
            "Download and extract the game client again?",
            isPresented: $confirmReinstall, titleVisibility: .visible
        ) {
            Button("Reinstall Client", role: .destructive) { model.install(reinstallClient: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This re-downloads about 4.8 GB and overwrites the files in the game folder.")
        }
        .confirmationDialog(
            "Quit the running game?", isPresented: $confirmQuit, titleVisibility: .visible
        ) {
            Button("Quit Game", role: .destructive) { model.quitGame() }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("This shuts down everything in the Wine prefix. Unsaved progress is lost.")
        }
        .confirmationDialog(
            "Move the installation to the Trash?",
            isPresented: $confirmClear, titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { model.clearInstallation() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(clearMessage)
        }
        .sheet(isPresented: $editingClientURL) { clientURLSheet }
        .onAppear { model.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 26))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ragnarok Online LATAM")
                    .font(.title3.weight(.semibold))
                Button {
                    model.revealInstallFolder()
                } label: {
                    Text(model.installFolder.path(percentEncoded: false)
                        .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .buttonStyle(.plain)
                .help("Show the installation folder in Finder")
            }
            Spacer()
            actionsMenu
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var actionsMenu: some View {
        Menu {
            Button("Show Installation Folder in Finder") { model.revealInstallFolder() }
            Button("Show Game Folder in Finder") { model.revealGameFolder() }
                .disabled(!model.status.clientReady)
            Divider()
            Button("Reinstall Game Client…") { confirmReinstall = true }
                .disabled(model.phase.isBusy)
            Button("Client URL…") { editingClientURL = true }
            Divider()
            Button("Re-apply GameGuard Workaround") { model.reapplyWintrustPatch() }
                .disabled(!model.status.wineReady || model.phase.isBusy)
            Button("Restore Original wintrust.dll") { model.restoreWintrust() }
                .disabled(!model.status.wineReady || model.phase.isBusy)
            Divider()
            Button("Copy Log") { model.copyLog() }
                .disabled(model.log.isEmpty)
            Divider()
            Button("Clear Installation Folder…", role: .destructive) { confirmClear = true }
                .disabled(model.phase.isBusy || !model.hasSomethingInstalled)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
    }

    // MARK: - Checklist

    private var checklist: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.status.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 48) }
                HStack(spacing: 12) {
                    Image(systemName: symbol(item.state))
                        .font(.system(size: 15))
                        .foregroundStyle(color(item.state))
                        .frame(width: 20)
                    Text(item.title)
                    Spacer()
                    Text(item.detail)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
        .padding(.vertical, 4)
    }

    private func symbol(_ state: Status.State) -> String {
        switch state {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .missing: "circle.dashed"
        }
    }

    private func color(_ state: Status.State) -> Color {
        switch state {
        case .ok: .green
        case .warning: .orange
        case .missing: .secondary
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                if model.phase.isBusy {
                    ProgressView().controlSize(.small)
                }
                Text(model.statusLine)
                    .font(.callout)
                    .foregroundStyle(model.failure == nil ? .primary : Color.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            if let progress = model.progress {
                VStack(spacing: 4) {
                    if let fraction = progress.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                    HStack {
                        Text(transferred(progress))
                        Spacer()
                        if progress.bytesPerSecond > 0 {
                            Text(rate(progress.bytesPerSecond))
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                switch model.phase {
                case .working:
                    Button("Cancel") { model.cancel() }
                        .controlSize(.large)
                case .running:
                    Button("Quit Game") { confirmQuit = true }
                        .controlSize(.large)
                case .idle:
                    Button(model.needsInstall ? "Install" : "Repair") { model.install() }
                        .controlSize(.large)
                }
                Spacer()
                Button {
                    model.play()
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canPlay)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func transferred(_ progress: DownloadProgress) -> String {
        let done = ByteCountFormatter.string(
            fromByteCount: progress.completed, countStyle: .file)
        guard let total = progress.total else { return done }
        return "\(done) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
    }

    private func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    // MARK: - Log

    private var logSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showLog.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(showLog ? 90 : 0))
                    Text("Log")
                        .font(.callout)
                    if !showLog, let last = model.log.last {
                        Text(last.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if showLog {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(model.log) { line in
                                Text(line.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(
                                        line.text.hasPrefix("==>") ? Color.accentColor :
                                        (line.text.hasPrefix("error:") ? .red : .secondary))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                    .frame(height: 180)
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: model.log.count) {
                        if let last = model.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var clearMessage: String {
        let size = model.installedSizeText.map { " (\($0))" } ?? ""
        return "Everything in \(model.installFolder.path(percentEncoded: false))\(size) goes "
            + "to the Trash: the Wine build, the prefix, the game client and its settings. "
            + "Installing again downloads it all afresh."
    }

    // MARK: - Sheets

    private var clientURLSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Client download URL")
                .font(.headline)
            Text("Point this at another build to install it instead. "
                 + "Use Reinstall Game Client afterwards.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("URL", text: $model.clientURLText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .font(.system(size: 11, design: .monospaced))
            HStack {
                Button("Reset to Default") {
                    model.clientURLText = Paths.defaultClientURL.absoluteString
                }
                Spacer()
                Button("Done") { editingClientURL = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
