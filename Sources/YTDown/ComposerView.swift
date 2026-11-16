import AppKit
import SwiftUI

struct ComposerView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DownloadManager.self) private var manager
    @Binding var showQueue: Bool

    @State private var urlText = ""
    @State private var info: MediaInfo?
    @State private var fetchedURL: String?
    @State private var isFetching = false
    @State private var errorText: String?
    @State private var options = DownloadOptions()
    @State private var clipboardSuggestion: String?
    @State private var showCommand = false
    @State private var addedToast = false
    @State private var fetchTask: Task<Void, Never>?
    @State private var missingTools: [ToolInstaller.Tool] = []
    @State private var installer = ToolInstaller.shared
    @State private var updater = Updater.shared
    @State private var dismissedUpdate: String?
    @State private var dismissedClipboardChange = -1   // don't re-suggest a clipboard link once it's been used
    @FocusState private var urlFocused: Bool

    private var trimmedURL: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var urlLooksValid: Bool {
        guard let u = URL(string: trimmedURL), let scheme = u.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && u.host != nil
    }
    private var urlHasPlaylist: Bool {
        !isBatch && (trimmedURL.contains("list=") || trimmedURL.contains("/playlist"))
    }
    /// More than one link pasted → batch mode (everything queued with the same settings).
    private var batchURLs: [String] {
        let urls = YTDLP.extractURLs(from: urlText)
        return urls.count > 1 ? urls : []
    }
    private var isBatch: Bool { !batchURLs.isEmpty }
    private var canDownload: Bool {
        if isBatch { return options.mode != .custom }
        return urlLooksValid && (options.mode != .custom || options.customFormatID != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                updateBanner
                if !missingTools.isEmpty { dependencyBanner }
                urlBar
                if urlHasPlaylist && !trimmedURL.contains("/playlist") { playlistToggle }
                if let clipboardSuggestion, urlText.isEmpty { clipboardChip(clipboardSuggestion) }
                if let errorText { errorBanner(errorText) }
                if isFetching { loadingCard }
                if isBatch {
                    BatchCard(urls: batchURLs)
                } else if let info, !isFetching {
                    PreviewCard(info: info)
                }
                ModePicker(mode: $options.mode, customAvailable: !isBatch && info != nil && !(info?.isPlaylist ?? false))
                OptionsPanel(options: $options, info: info)
                ExtrasPanel(options: $options)
                footer
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .mask {
            // Fade content out as it scrolls up under the transparent title bar.
            VStack(spacing: 0) {
                Color.clear.frame(height: 26)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 34)
                Color.black
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) {
            if let note = installer.updateNote {
                Label(note, systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassBar(cornerRadius: 22)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation { installer.updateNote = nil }
                    }
            } else if addedToast {
                Label("Added to downloads", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassBar(cornerRadius: 22)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            options = settings.lastOptions
            options.includePlaylist = false
            options.customFormatID = nil
            urlFocused = true
            checkClipboard()
            checkTools()
        }
        .onChange(of: options) { _, new in settings.lastOptions = new }
        .onChange(of: urlText) { _, _ in scheduleAutoFetch() }
        .onChange(of: options.includePlaylist) { _, _ in
            if info != nil { fetch() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkClipboard()
            checkTools()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            urlText = urls.map(\.absoluteString).joined(separator: "\n")
            if urls.count == 1 { fetch() }
            return true
        }
        .sheet(isPresented: $showCommand) { CommandSheet(command: commandPreview) }
        .onChange(of: installer.revision) { _, _ in checkTools() }
    }

    // MARK: Sections

    private var hero: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .glass(RoundedRectangle(cornerRadius: 15, style: .continuous), tint: .red.opacity(0.9))
            VStack(alignment: .leading, spacing: 2) {
                Text("YTDown").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Paste a link, pick a format, and go.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Shown when a new version has been downloaded (or found, with automatic installs off).
    @ViewBuilder
    private var updateBanner: some View {
        switch updater.phase {
        case .ready(let release) where dismissedUpdate != release.version:
            updateCard(release, title: "YTDown \(release.version) is ready",
                       detail: "It installs when you restart — or automatically the next time you quit.") {
                Button("Restart Now") { updater.installAndRelaunch() }
                    .prominentGlassButton(tint: .blue).buttonBorderShape(.capsule)
            }
        case .available(let release) where dismissedUpdate != release.version:
            updateCard(release, title: "YTDown \(release.version) is available",
                       detail: Updater.installBlocker ?? "A newer version has been published on GitHub.") {
                if Updater.installBlocker == nil {
                    Button("Download Update") { Task { await updater.download(release) } }
                        .prominentGlassButton(tint: .blue).buttonBorderShape(.capsule)
                } else {
                    Link("View Release", destination: release.page)
                }
            }
        case .downloading(let release, let progress):
            HStack(spacing: 12) {
                ProgressView(value: progress).tint(.blue).frame(maxWidth: 220)
                Text("Downloading YTDown \(release.version)… \(Int(progress * 100))%")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            .card(padding: 14, tint: .blue.opacity(0.14))
        default:
            EmptyView()
        }
    }

    private func updateCard<Action: View>(_ release: Updater.Release, title: String, detail: String,
                                          @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.app.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .glass(Circle(), tint: .blue.opacity(0.9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Link("What's New", destination: release.page).font(.callout)
            action()
            Button { withAnimation { dismissedUpdate = release.version } } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 20, height: 20)
            }
            .glassCircleButton()
            .help("Later")
        }
        .card(padding: 14, tint: .blue.opacity(0.14))
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private var urlBar: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: isBatch ? "link.badge.plus" : "link")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                    TextField("Paste a link — or several, one per line", text: $urlText, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($urlFocused)
                        .onSubmit { fetch() }
                    if !urlText.isEmpty {
                        Button { reset() } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .frame(width: 22, height: 22)
                        }
                        .glassCircleButton()
                        .help("Clear")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .glass(RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: true)

                Button {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        let urls = YTDLP.extractURLs(from: s)
                        urlText = urls.count > 1 ? urls.joined(separator: "\n") : s.trimmingCharacters(in: .whitespacesAndNewlines)
                        if urls.count <= 1 { fetch() }
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .padding(.horizontal, 4).padding(.vertical, 5)
                }
                .glassButton()
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .help("Paste from clipboard and fetch (⇧⌘V)")

                Button { fetch() } label: {
                    Group {
                        if isFetching {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Fetch").fontWeight(.semibold)
                        }
                    }
                    .frame(width: 48, height: 20)
                    .padding(.vertical, 3)
                }
                .prominentGlassButton()
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(!urlLooksValid || isFetching || isBatch)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: urlText.isEmpty)
    }

    private var playlistToggle: some View {
        HStack(spacing: 10) {
            GlassChip(title: "Download entire playlist", symbol: "list.bullet.rectangle", isOn: $options.includePlaylist)
            Text("This link is part of a playlist.").font(.callout).foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
    }

    private func clipboardChip(_ link: String) -> some View {
        Button {
            urlText = link
            fetch()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text("Use copied link")
                    .fontWeight(.medium)
                Text(link).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glass(Capsule(), interactive: true)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).textSelection(.enabled)
            Spacer()
            Button { withAnimation { errorText = nil } } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 20, height: 20)
            }
            .glassCircleButton()
        }
        .font(.callout)
        .card(padding: 14, tint: .orange.opacity(0.25))
    }

    private var loadingCard: some View {
        HStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.quaternary.opacity(0.6))
                .frame(width: 240, height: 135)
                .overlay(ProgressView())
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 5).fill(.quaternary).frame(height: 18)
                RoundedRectangle(cornerRadius: 5).fill(.quaternary).frame(width: 180, height: 14)
                Text("Fetching video info…").font(.callout).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var footer: some View {
        GlassGroup(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    chooseFolder()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .glass(Circle(), tint: .blue.opacity(0.85))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Save to").font(.caption).foregroundStyle(.secondary)
                            Text(settings.outputDirectory.lastPathComponent).fontWeight(.medium)
                        }
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glass(Capsule(), interactive: true)
                .help(settings.outputDirectory.path)
                .contextMenu {
                    Button("Show in Finder") { NSWorkspace.shared.open(settings.outputDirectory) }
                    Button("Choose Folder…") { chooseFolder() }
                }

                Button { showCommand = true } label: {
                    Image(systemName: "terminal")
                        .frame(width: 22, height: 22)
                }
                .glassCircleButton()
                .controlSize(.large)
                .disabled(!urlLooksValid && !isBatch)
                .help("Show the yt-dlp command that will run")

                Spacer()

                if !isBatch, let size = info?.estimatedSize(for: effectiveOptions) {
                    Label("≈ \(formatBytes(size))", systemImage: "internaldrive")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .glass(Capsule())
                        .help("Estimated file size, based on the sizes YouTube reports")
                        .animation(.snappy, value: size)
                }

                Button(action: startDownload) {
                    Label(downloadButtonTitle, systemImage: "arrow.down.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                }
                .prominentGlassButton()
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!canDownload)
                .help("Start download (⌘↩)")
            }
        }
        .padding(.top, 4)
    }

    private var downloadButtonTitle: String {
        if isBatch { return "Download \(batchURLs.count) Links" }
        if options.includePlaylist || (info?.isPlaylist ?? false) {
            return info.map { "Download \($0.entryCount) Items" } ?? "Download Playlist"
        }
        switch options.mode {
        case .audio: return options.audioFormat == .best ? "Download Audio" : "Download \(options.audioFormat.rawValue.uppercased())"
        default: return "Download"
        }
    }

    private var commandPreview: String {
        let args = YTDLP.downloadArguments(url: batchURLs.first ?? trimmedURL, options: effectiveOptions, formats: info?.formats ?? [], settings: settings)
        return YTDLP.shellCommand(args)
    }

    private var effectiveOptions: DownloadOptions {
        var o = options
        if info?.isPlaylist == true { o.includePlaylist = true }
        return o
    }

    // MARK: Actions

    private func scheduleAutoFetch() {
        guard settings.autoFetchOnPaste else { return }
        fetchTask?.cancel()
        if isBatch {
            if options.mode == .custom { options.mode = .video }
            info = nil
            errorText = nil
            isFetching = false
            fetchedURL = nil
            return
        }
        let current = trimmedURL
        guard urlLooksValid, current != fetchedURL else { return }
        fetchTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, current == trimmedURL else { return }
            fetch()
        }
    }

    private func fetch() {
        guard urlLooksValid else {
            if !trimmedURL.isEmpty { errorText = "That doesn't look like a valid link." }
            return
        }
        let target = trimmedURL
        let playlist = options.includePlaylist || target.contains("/playlist")
        fetchedURL = target
        errorText = nil
        isFetching = true
        clipboardSuggestion = nil
        dismissedClipboardChange = NSPasteboard.general.changeCount
        fetchTask?.cancel()
        fetchTask = Task {
            do {
                let result = try await YTDLP.fetchInfo(url: target, playlist: playlist, settings: settings)
                guard !Task.isCancelled, target == trimmedURL else { return }
                withAnimation(.spring(duration: 0.35)) {
                    info = result
                    options.customFormatID = nil
                    if result.isPlaylist && options.mode == .custom { options.mode = .video }
                    isFetching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation {
                    info = nil
                    errorText = error.localizedDescription
                    isFetching = false
                }
            }
        }
    }

    private func startDownload() {
        guard canDownload else { return }
        if isBatch {
            var o = options
            o.includePlaylist = false
            for url in batchURLs { manager.enqueue(url: url, info: nil, options: o) }
        } else {
            manager.enqueue(url: trimmedURL, info: info, options: effectiveOptions)
        }
        withAnimation(.spring) {
            addedToast = true
            showQueue = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { addedToast = false }
        }
    }

    private func reset() {
        fetchTask?.cancel()
        withAnimation {
            urlText = ""
            info = nil
            fetchedURL = nil
            errorText = nil
            isFetching = false
            options.includePlaylist = false
        }
        urlFocused = true
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.outputDirectory
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputDirectory = url
        }
    }

    private func checkTools() {
        let missing = installer.missingTools(settings: settings)
        withAnimation(.spring) { missingTools = missing }
    }

    private var dependencyBanner: some View {
        let names = missingTools.map(\.rawValue)
        let needsYTDLP = missingTools.contains(.ytdlp)
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .glass(Circle(), tint: .orange.opacity(0.9))
            VStack(alignment: .leading, spacing: 8) {
                Text(needsYTDLP ? "One-time setup needed" : "\(names.joined(separator: " & ")) not found")
                    .font(.headline)
                Text(needsYTDLP
                     ? "YTDown uses yt-dlp to download and ffmpeg to merge video and convert audio. Install them with one click (about 170 MB, checksum-verified)."
                     : "ffmpeg is needed to merge video with audio and to convert to MP3.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                switch installer.phase {
                case .downloading(let tool, let progress):
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress).tint(.orange)
                        Text("Downloading \(tool.rawValue)… \(Int(progress * 100))%")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 360)
                case .verifying(let tool):
                    Label("Verifying \(tool.rawValue)…", systemImage: "checkmark.shield")
                        .font(.caption).foregroundStyle(.secondary)
                default:
                    HStack(spacing: 10) {
                        Button {
                            Task { await installer.install(missingTools) }
                        } label: {
                            Label("Install \(names.joined(separator: ", "))", systemImage: "arrow.down.app.fill")
                                .padding(.horizontal, 6).padding(.vertical, 3)
                        }
                        .prominentGlassButton(tint: .orange)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)

                        if YTDLP.locate("brew") != nil {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("brew install yt-dlp ffmpeg", forType: .string)
                            } label: {
                                Label("Copy Homebrew command", systemImage: "doc.on.doc")
                            }
                            .glassButton()
                            .buttonBorderShape(.capsule)
                        }
                        SettingsLink { Text("Set Path…") }
                            .glassButton()
                            .buttonBorderShape(.capsule)
                    }
                    if case .failed(let message) = installer.phase {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 18, tint: .orange.opacity(0.18))
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private func checkClipboard() {
        guard urlText.isEmpty, NSPasteboard.general.changeCount != dismissedClipboardChange,
              let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              s.count < 500,
              let u = URL(string: s), let host = u.host?.lowercased(),
              host.contains("youtube.com") || host.contains("youtu.be") || host.contains("vimeo.com")
                || host.contains("soundcloud.com") || host.contains("tiktok.com") || host.contains("x.com")
                || host.contains("twitter.com") || host.contains("instagram.com")
        else { return }
        withAnimation { clipboardSuggestion = s }
    }
}

// MARK: - Preview card

struct PreviewCard: View {
    let info: MediaInfo

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            AsyncImage(url: info.thumbnail) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: Rectangle().fill(.quaternary).overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
                }
            }
            .frame(width: 240, height: 135)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if let d = info.durationText {
                    Text(d)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 5))
                        .padding(6)
                }
            }
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 8) {
                if info.isPlaylist {
                    Label("Playlist · \(info.entryCount) videos", systemImage: "list.bullet.rectangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.red.gradient, in: Capsule())
                }
                Text(info.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                    .textSelection(.enabled)
                if let up = info.uploader {
                    Label(up, systemImage: "person.crop.circle").foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    if let views = info.viewCount {
                        Label(views.formatted(.number.notation(.compactName)) + " views", systemImage: "eye")
                    }
                    if let top = info.availableHeights.first {
                        Label("Up to \(String(top))p", systemImage: "sparkles.tv")
                    }
                    if !info.formats.isEmpty {
                        Label("\(info.formats.count) formats", systemImage: "square.stack.3d.up")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .card()
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

// MARK: - Command sheet

struct CommandSheet: View {
    let command: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("yt-dlp command").font(.title2.weight(.semibold))
            Text("This is exactly what YTDown will run. You can paste it into Terminal.")
                .foregroundStyle(.secondary)
            ScrollView {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 160)
            .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    withAnimation { copied = true }
                } label: {
                    Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .glassButton().buttonBorderShape(.capsule)
                Button("Done") { dismiss() }
                    .prominentGlassButton().buttonBorderShape(.capsule)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640)
    }
}

// MARK: - Batch card

struct BatchCard: View {
    let urls: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(urls.count) links — all will download with the settings below", systemImage: "square.stack.3d.down.right")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(urls.prefix(6).enumerated()), id: \.offset) { i, url in
                    HStack(spacing: 8) {
                        Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 18, alignment: .trailing)
                        Text(url).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                if urls.count > 6 {
                    Text("and \(urls.count - 6) more…").font(.callout).foregroundStyle(.tertiary).padding(.leading, 26)
                }
            }
        }
        .card()
        .transition(.opacity)
    }
}
