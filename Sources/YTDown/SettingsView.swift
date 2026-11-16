import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
            NetworkSettings().tabItem { Label("Network", systemImage: "network") }
            ToolsSettings().tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            UpdateSettings().tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 560)
        .padding(.vertical, 8)
    }
}

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            LabeledContent("Download folder") {
                HStack {
                    Text(settings.outputDirectory.path)
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let u = panel.url { settings.outputDirectory = u }
                    }
                }
            }
            Section {
                TextField("File name", text: $settings.filenameTemplate)
                    .font(.body.monospaced())
                TextField("Playlist file name", text: $settings.playlistTemplate)
                    .font(.body.monospaced())
                Button("Restore Defaults") {
                    settings.filenameTemplate = AppSettings.defaultTemplate
                    settings.playlistTemplate = AppSettings.defaultPlaylistTemplate
                }
            } header: {
                Text("Naming")
            } footer: {
                Text("yt-dlp output templates. Useful fields: %(title)s, %(id)s, %(uploader)s, %(upload_date)s, %(playlist_index)s.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Behavior") {
                Stepper("Simultaneous downloads: \(settings.maxConcurrent)", value: $settings.maxConcurrent, in: 1...6)
                Toggle("Fetch video info automatically when a link is pasted", isOn: $settings.autoFetchOnPaste)
                Toggle("Notify when downloads finish", isOn: $settings.notifyOnFinish)
            }
            Section {
                Toggle("Show YTDown in the menu bar", isOn: $settings.showMenuBarIcon)
                Toggle("Keep the Mac awake while downloading", isOn: $settings.preventSleep)
            } header: {
                Text("Background")
            } footer: {
                Text("With the menu bar item on, closing the window keeps downloads running; quit from the menu bar or with ⌘Q.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Backdrop") {
                HStack(spacing: 12) {
                    ForEach(BackdropStyle.allCases) { style in
                        let selected = settings.backdropStyle == style
                        Button {
                            settings.backdropStyle = style
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(LinearGradient(colors: [style.palette[0], style.palette[2], style.palette[4]],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(height: 46)
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(selected ? Color.accentColor : .primary.opacity(0.1), lineWidth: selected ? 2.5 : 1))
                                Text(style.label)
                                    .font(.caption.weight(selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? .primary : .secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(style.label) backdrop")
                    }
                }
                .padding(.vertical, 4)
                Toggle("Animate the backdrop", isOn: $settings.animateBackdrop)
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdateSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var updater = Updater.shared

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .glass(Circle(), tint: .blue.opacity(0.9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YTDown \(Updater.currentVersion ?? "(development build)")").fontWeight(.semibold)
                        Text(statusText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    actionButton
                }
                if case .downloading(_, let p) = updater.phase {
                    ProgressView(value: p).tint(.blue)
                }
                if case .failed(let message) = updater.phase {
                    Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
                }
                if let blocker = Updater.installBlocker {
                    Label(blocker, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Check for updates automatically", isOn: $settings.autoCheckUpdates)
                Toggle("Download and install updates automatically", isOn: $settings.autoInstallUpdates)
                    .disabled(!settings.autoCheckUpdates)
            } footer: {
                Text("Updates come from github.com/\(Updater.repository) and are only installed if their signature verifies. A downloaded update is applied the next time YTDown restarts or quits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Link("Release notes on GitHub", destination: Updater.releasesPage)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch updater.phase {
        case .checking: return "Checking…"
        case .available(let r): return "Version \(r.version) is available"
        case .downloading(let r, let p): return "Downloading \(r.version)… \(Int(p * 100))%"
        case .ready(let r): return "Version \(r.version) is ready to install"
        case .upToDate: return "You're up to date" + (lastCheckedText.map { " · checked \($0)" } ?? "")
        case .idle, .failed: return lastCheckedText.map { "Last checked \($0)" } ?? "Not checked yet"
        }
    }

    private var lastCheckedText: String? {
        updater.lastChecked?.formatted(.relative(presentation: .named))
    }

    @ViewBuilder
    private var actionButton: some View {
        switch updater.phase {
        case .ready:
            Button("Restart to Update") { updater.installAndRelaunch() }
                .prominentGlassButton(tint: .blue).buttonBorderShape(.capsule)
        case .available(let release):
            if Updater.installBlocker == nil {
                Button("Download") { Task { await updater.download(release) } }
                    .prominentGlassButton(tint: .blue).buttonBorderShape(.capsule)
            } else {
                Link("View Release", destination: release.page)
            }
        default:
            Button(updater.isBusy ? "Checking…" : "Check Now") { Task { await updater.check(userInitiated: true) } }
                .glassButton().buttonBorderShape(.capsule)
                .disabled(updater.isBusy)
        }
    }
}

private struct NetworkSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                TextField("Speed limit", text: $settings.rateLimit, prompt: Text("Unlimited"))
            } footer: {
                Text("Maximum download speed per download, e.g. 5M (5 MB/s) or 500K. Leave empty for unlimited.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Use cookies from", selection: $settings.cookieBrowser) {
                    ForEach(CookieBrowser.allCases) { b in Text(b.label).tag(b) }
                }
            } footer: {
                Text("Lets yt-dlp access age-restricted, members-only or private videos you can see while signed in. Safari may require Full Disk Access for YTDown.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ToolsSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var version: String?
    @State private var updating = false
    @State private var updateOutput: String?
    @State private var installer = ToolInstaller.shared

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .glass(Circle(), tint: .orange.opacity(0.9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Built-in tools").fontWeight(.semibold)
                        Text(managedSummary).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task {
                            await installer.install(ToolInstaller.Tool.allCases)
                            version = await YTDLP.version(settings: settings)
                        }
                    } label: {
                        Text(installer.isBusy ? "Installing…" : (hasManaged ? "Reinstall Latest" : "Install"))
                    }
                    .prominentGlassButton(tint: .orange)
                    .buttonBorderShape(.capsule)
                    .disabled(installer.isBusy)
                }
                switch installer.phase {
                case .downloading(let tool, let p):
                    ProgressView(value: p) { Text("Downloading \(tool.rawValue)… \(Int(p * 100))%").font(.caption) }
                        .tint(.orange)
                case .verifying(let tool):
                    Label("Verifying \(tool.rawValue) checksum…", systemImage: "checkmark.shield").font(.caption)
                case .failed(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
                case .done:
                    Label("Installed and verified.", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
                case .idle:
                    EmptyView()
                }
            } footer: {
                Text("Downloads the official yt-dlp release and static ffmpeg/ffprobe builds into Application Support, verifying each SHA-256 checksum. A Homebrew install, if present, is preferred.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("yt-dlp") {
                LabeledContent("Detected") {
                    Text(YTDLP.locate("yt-dlp", override: settings.ytdlpPath) ?? "Not found")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Version") { Text(version ?? "…").foregroundStyle(.secondary) }
                TextField("Custom path (optional)", text: $settings.ytdlpPath, prompt: Text("/opt/homebrew/bin/yt-dlp"))
                HStack {
                    Button(updating ? "Updating…" : "Update yt-dlp") { update() }
                        .glassButton()
                        .buttonBorderShape(.capsule)
                        .disabled(updating)
                    Spacer()
                }
                if let updateOutput {
                    Text(updateOutput).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Section("ffmpeg") {
                LabeledContent("Detected") {
                    Text(YTDLP.locate("ffmpeg", override: settings.ffmpegPath) ?? "Not found — merging & MP3 conversion need ffmpeg")
                        .foregroundStyle(.secondary)
                }
                TextField("Custom path (optional)", text: $settings.ffmpegPath, prompt: Text("/opt/homebrew/bin/ffmpeg"))
            }
        }
        .formStyle(.grouped)
        .task { version = await YTDLP.version(settings: settings) ?? "Not installed" }
    }

    private var hasManaged: Bool {
        FileManager.default.fileExists(atPath: ToolInstaller.binDirectory.appendingPathComponent("yt-dlp").path)
    }

    private var managedSummary: String {
        _ = installer.revision   // re-evaluate after installs
        let names = ToolInstaller.Tool.allCases.map(\.rawValue).filter {
            FileManager.default.fileExists(atPath: ToolInstaller.binDirectory.appendingPathComponent($0).path)
        }
        return names.isEmpty ? "Not installed — using system tools" : "Installed: " + names.joined(separator: ", ")
    }

    private func update() {
        guard let bin = YTDLP.locate("yt-dlp", override: settings.ytdlpPath) else { return }
        updating = true
        Task {
            // Homebrew installs must be updated through brew; standalone binaries self-update.
            let result: YTDLP.Output?
            if bin.hasPrefix("/opt/homebrew") || bin.hasPrefix("/usr/local"),
               let brew = YTDLP.locate("brew") {
                result = try? await YTDLP.run(brew, ["upgrade", "yt-dlp"])
            } else {
                result = try? await YTDLP.run(bin, ["-U"])
            }
            let text = [result.map { String(decoding: $0.stdout, as: UTF8.self) }, result?.stderr]
                .compactMap { $0 }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            updateOutput = text.isEmpty ? "Already up to date." : String(text.suffix(600))
            version = await YTDLP.version(settings: settings)
            updating = false
        }
    }
}
