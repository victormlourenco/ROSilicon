import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: LauncherModel
    @StateObject private var modifiers = ModifierKeys()
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
            Strings.reinstallTitle,
            isPresented: $confirmReinstall, titleVisibility: .visible
        ) {
            Button(Strings.reinstallConfirm, role: .destructive) {
                model.install(reinstallClient: true)
            }
            Button(Strings.cancel, role: .cancel) {}
        } message: {
            Text(Strings.reinstallMessage)
        }
        .confirmationDialog(
            Strings.quitTitle, isPresented: $confirmQuit, titleVisibility: .visible
        ) {
            Button(Strings.quitConfirm, role: .destructive) { model.quitGame() }
            Button(Strings.quitKeepPlaying, role: .cancel) {}
        } message: {
            Text(Strings.quitMessage)
        }
        .confirmationDialog(
            Strings.clearTitle, isPresented: $confirmClear, titleVisibility: .visible
        ) {
            Button(Strings.clearConfirm, role: .destructive) { model.clearInstallation() }
            Button(Strings.cancel, role: .cancel) {}
        } message: {
            Text(clearMessage)
        }
        .sheet(isPresented: $editingClientURL) { clientURLSheet }
        .onAppear {
            model.refresh()
            modifiers.watch()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 26))
                .foregroundStyle(.tint)
            Text(Strings.appTitle)
                .font(.title3.weight(.semibold))
            Spacer()
            actionsMenu
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var actionsMenu: some View {
        Menu {
            Button(Strings.menuShowGameFolder) { model.revealGameFolder() }
                .disabled(!model.status.clientReady)
            if modifiers.optionHeld {
                Button(Strings.menuShowInstallFolder) { model.revealInstallFolder() }
            }
            Divider()
            Button(Strings.menuReinstallClient) { confirmReinstall = true }
                .disabled(model.phase.isBusy)
            if modifiers.optionHeld {
                Button(Strings.menuClientURL) { editingClientURL = true }
            }
            Divider()
            Button(Strings.menuReapplyPatch) { model.reapplyWintrustPatch() }
                .disabled(!model.status.wineReady || model.phase.isBusy)
            if modifiers.optionHeld {
                Button(Strings.menuRestoreWintrust) { model.restoreWintrust() }
                    .disabled(!model.status.wineReady || model.phase.isBusy)
                Divider()
                Toggle(Strings.menuMetalHUD, isOn: $model.metalHUD)
                Divider()
                Button(Strings.menuCopyLog) { model.copyLog() }
                    .disabled(model.log.isEmpty)
            }
            Divider()
            Button(Strings.menuClearInstall, role: .destructive) { confirmClear = true }
                .disabled(model.phase.isBusy || !model.hasSomethingInstalled)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Strings.menuMore)
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
                    Button(Strings.cancel) { model.cancel() }
                        .controlSize(.large)
                case .running:
                    Button(Strings.quitGame) { confirmQuit = true }
                        .controlSize(.large)
                case .idle:
                    Button(model.needsInstall ? Strings.install : Strings.repair) {
                        model.install()
                    }
                    .controlSize(.large)
                }
                Spacer()
                Button {
                    model.play()
                } label: {
                    Label(Strings.play, systemImage: "play.fill")
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
        return Strings.transferred(
            done, ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
    }

    private func rate(_ bytesPerSecond: Double) -> String {
        Strings.perSecond(
            ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file))
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
                    Text(Strings.log)
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
                                    .foregroundStyle(colour(line.kind))
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

    private func colour(_ kind: LauncherModel.LogLine.Kind) -> Color {
        switch kind {
        case .plain: .secondary
        case .step: .accentColor
        case .failure: .red
        }
    }

    private var clearMessage: String {
        let folder = model.installFolder.path(percentEncoded: false)
        guard let size = model.installedSizeText else {
            return Strings.clearMessageNoSize(folder)
        }
        return Strings.clearMessage(folder, size)
    }

    // MARK: - Sheets

    private var clientURLSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.clientURLTitle)
                .font(.headline)
            Text(Strings.clientURLExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField(Strings.clientURLField, text: $model.clientURLText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .font(.system(size: 11, design: .monospaced))
            HStack {
                Button(Strings.clientURLReset) {
                    model.clientURLText = Paths.defaultClientURL.absoluteString
                }
                Spacer()
                Button(Strings.done) { editingClientURL = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
