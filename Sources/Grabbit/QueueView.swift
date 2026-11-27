import AppKit
import SwiftUI

struct QueueView: View {
    @Environment(DownloadManager.self) private var manager
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Downloads").font(.title3.weight(.semibold))
                if manager.activeCount > 0 {
                    Text("\(manager.activeCount) active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .glass(Capsule(), tint: .red.opacity(0.85))
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                GlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            NSWorkspace.shared.open(settings.outputDirectory)
                        } label: {
                            Image(systemName: "folder")
                                .font(.callout.weight(.semibold))
                                .frame(width: 30, height: 30)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glass(Circle(), interactive: true)
                        .help("Open download folder")
                        Menu {
                            Button("Clear Finished") { manager.clearFinished() }
                                .disabled(!manager.items.contains { $0.status.isDone })
                            Button("Cancel All", role: .destructive) { manager.cancelAll() }
                                .disabled(manager.pendingCount == 0)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.callout.weight(.semibold))
                                .frame(width: 30, height: 30)
                                .contentShape(Circle())
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .glass(Circle(), interactive: true)
                        .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .animation(.spring, value: manager.activeCount)

            if let overall = manager.overallProgress, manager.pendingCount > 1 || manager.activeCount > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    GlassProgressBar(value: overall, tint: .red)
                    HStack {
                        Text("\(manager.pendingCount) remaining · \(Int(overall * 100))% overall")
                        Spacer()
                        if manager.totalSpeed > 0 { Text(formatBytes(Int64(manager.totalSpeed)) + "/s") }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .transition(.opacity)
            }

            if manager.items.isEmpty {
                ContentUnavailableView {
                    Label("No downloads yet", systemImage: "arrow.down.circle.dotted")
                } description: {
                    Text("Downloads you start will appear here with live progress.")
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(manager.items) { item in
                            DownloadRow(item: item)
                                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                        }
                    }
                    .padding(12)
                    .animation(.spring(duration: 0.35), value: manager.items.map(\.id))
                }
            }
        }
    }
}

struct DownloadRow: View {
    @Environment(DownloadManager.self) private var manager
    @Environment(Player.self) private var player
    let item: DownloadItem
    @State private var showLog = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                thumbnail
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        SiteBadge(link: item.url, compact: true)
                        Image(systemName: item.options.mode.symbol)
                        Text(item.summary).lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                actions
            }

            switch item.status {
            case .queued:
                statusLine("Waiting in queue…", symbol: "clock", color: .secondary)
            case .downloading:
                GlassProgressBar(value: item.progress, tint: .red)
                HStack {
                    Text(progressText)
                    Spacer()
                    Text(rateText)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            case .processing(let what):
                GlassProgressBar(value: nil, tint: .purple)
                statusLine(what + "…", symbol: "gearshape.2", color: .purple)
            case .finished where !item.outputFiles.isEmpty && existingFiles.isEmpty:
                statusLine("File was moved or deleted", symbol: "questionmark.folder", color: .secondary)
            case .finished:
                statusLine(finishedText, symbol: "checkmark.circle.fill", color: .green)
            case .failed(let msg):
                statusLine(msg, symbol: "exclamationmark.octagon.fill", color: .red)
                    .lineLimit(3)
                    .textSelection(.enabled)
            case .cancelled:
                statusLine("Cancelled", symbol: "xmark.circle", color: .secondary)
            }
        }
        .padding(14)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: rowTint, interactive: true)
        .scaleEffect(hovering ? 1.01 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu { contextItems }
        .sheet(isPresented: $showLog) { LogSheet(item: item) }
        .onTapGesture(count: 2) { playOrPause() }
        .onDrag {
            // Drag a finished download straight into Finder, Mail, Final Cut, etc.
            guard let f = existingFiles.last else { return NSItemProvider() }
            return NSItemProvider(contentsOf: f) ?? NSItemProvider()
        }
    }

    private var rowTint: Color? {
        switch item.status {
        case .finished: return .green.opacity(0.12)
        case .failed: return .red.opacity(0.12)
        default: return nil
        }
    }

    /// Whether this row's file is the one loaded in the in-app player.
    private var isCurrent: Bool { player.url != nil && player.url == existingFiles.last }

    /// Plays the finished file in the Now Playing tab, or pauses/resumes it if it is already there.
    private func playOrPause() {
        guard case .finished = item.status, let f = existingFiles.last else { return }
        if isCurrent {
            player.toggle()
        } else {
            player.play(f, title: item.title, source: MediaSite.displayName(for: item.url) ?? "", artwork: item.thumbnail)
        }
    }

    private var existingFiles: [URL] {
        item.outputFiles.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private var thumbnail: some View {
        AsyncImage(url: item.thumbnail) { phase in
            if case .success(let img) = phase {
                img.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: item.options.mode.symbol).foregroundStyle(.tertiary))
            }
        }
        .frame(width: 76, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var actions: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 6) {
                switch item.status {
                case .queued, .downloading, .processing:
                    iconButton("xmark", help: "Cancel") { manager.cancel(item) }
                case .finished where existingFiles.isEmpty:
                    iconButton("arrow.clockwise", help: "Download again") { manager.retry(item) }
                    iconButton("trash", help: "Remove") { manager.remove(item) }
                case .finished:
                    iconButton("magnifyingglass", help: "Show in Finder") { reveal() }
                    iconButton(isCurrent && player.isPlaying ? "pause.fill" : "play.fill",
                               help: isCurrent && player.isPlaying ? "Pause" : "Play") { playOrPause() }
                case .failed, .cancelled:
                    iconButton("arrow.clockwise", help: "Retry") { manager.retry(item) }
                    iconButton("trash", help: "Remove") { manager.remove(item) }
                }
            }
        }
    }

    @ViewBuilder
    private var contextItems: some View {
        if !existingFiles.isEmpty {
            Button(isCurrent && player.isPlaying ? "Pause" : "Play") { playOrPause() }
            Button("Open in Default App") {
                if isCurrent { player.pause() }   // don't play the same file twice
                existingFiles.forEach { NSWorkspace.shared.open($0) }
            }
            Button("Show in Finder") { reveal() }
            Divider()
        }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url, forType: .string)
        }
        Button("Show Log…") { showLog = true }
        Divider()
        if item.status.isDone {
            Button("Retry") { manager.retry(item) }
            Button("Remove from List") { manager.remove(item) }
        } else {
            Button("Cancel Download", role: .destructive) { manager.cancel(item) }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 16, height: 16)
        }
        .glassCircleButton()
        .controlSize(.small)
        .help(help)
    }

    private func statusLine(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
    }

    private func reveal() {
        if existingFiles.isEmpty { return }
        NSWorkspace.shared.activateFileViewerSelecting(existingFiles)
    }

    private var progressText: String {
        var parts: [String] = []
        if let i = item.playlistIndex, let n = item.playlistCount { parts.append("\(i)/\(n)") }
        parts.append(item.stage)
        parts.append("\(Int(item.progress * 100))%")
        if let total = item.totalBytes { parts.append("of \(formatBytes(total))") }
        return parts.joined(separator: " · ")
    }

    private var rateText: String {
        var parts: [String] = []
        if let s = item.speed, s > 0 { parts.append(formatBytes(Int64(s)) + "/s") }
        if let e = item.eta { parts.append(formatDuration(Double(e)) + " left") }
        return parts.joined(separator: " · ")
    }

    private var finishedText: String {
        let files = item.outputFiles
        if files.count > 1 { return "Saved \(files.count) files" }
        if let f = files.first {
            let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map { " · " + formatBytes(Int64($0)) } ?? ""
            return f.lastPathComponent + size
        }
        return "Done"
    }
}

struct LogSheet: View {
    let item: DownloadItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log — \(item.title)").font(.headline).lineLimit(1)
            ScrollView {
                Text(item.log.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.log.joined(separator: "\n"), forType: .string)
                }
                .glassButton().buttonBorderShape(.capsule)
                Spacer()
                Button("Done") { dismiss() }
                    .prominentGlassButton().buttonBorderShape(.capsule)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 700, height: 440)
    }
}

/// A capsule progress bar: a glass track with a tinted, glowing fill. `nil` = indeterminate.
struct GlassProgressBar: View {
    let value: Double?
    var tint: Color = .red
    @State private var phase: CGFloat = -0.4

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                if let value {
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, w * min(max(value, 0), 1)))
                        .shadow(color: tint.opacity(0.5), radius: 4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: value)
                } else {
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0), tint, tint.opacity(0)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * 0.4)
                        .offset(x: w * phase)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { phase = 1.0 }
                        }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
    }
}
