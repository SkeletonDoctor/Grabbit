import AppKit
import Foundation
import Observation
import UserNotifications

@Observable
final class DownloadItem: Identifiable {
    enum Status: Equatable {
        case queued
        case downloading
        case processing(String)
        case finished
        case failed(String)
        case cancelled

        var isActive: Bool {
            switch self {
            case .downloading, .processing: return true
            default: return false
            }
        }
        var isDone: Bool {
            switch self {
            case .finished, .failed, .cancelled: return true
            default: return false
            }
        }
    }

    let id: UUID
    let url: String
    var title: String
    var thumbnail: URL?
    let options: DownloadOptions
    let arguments: [String]
    let createdAt: Date

    var status: Status = .queued
    var progress: Double = 0          // 0...1 for current file
    var speed: Double?                // bytes/sec
    var eta: Int?
    var totalBytes: Int64?
    var stage: String = ""
    var playlistIndex: Int?
    var playlistCount: Int?
    var outputFiles: [URL] = []
    var log: [String] = []

    @ObservationIgnored var process: Process?

    init(id: UUID = UUID(), createdAt: Date = Date(), url: String, title: String, thumbnail: URL?,
         options: DownloadOptions, arguments: [String]) {
        self.id = id
        self.createdAt = createdAt
        self.url = url
        self.title = title
        self.thumbnail = thumbnail
        self.options = options
        self.arguments = arguments
    }

    var summary: String {
        switch options.mode {
        case .audio:
            let fmt = options.audioFormat.label
            return options.audioFormat.isLossy ? "\(fmt) · \(options.audioBitrate.label)" : fmt
        case .video, .videoOnly:
            let q = options.quality == .best ? "Best" : "\(options.quality.rawValue)p"
            return "\(q) · \(options.container.rawValue.uppercased())" + (options.mode == .videoOnly ? " · no audio" : "")
        case .custom:
            return "Format \(options.customFormatID ?? "?")"
        }
    }
}

@MainActor
@Observable
final class DownloadManager {
    var items: [DownloadItem] = []
    let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        loadHistory()
    }

    var activeCount: Int { items.filter { $0.status.isActive }.count }
    var pendingCount: Int { items.filter { !$0.status.isDone }.count }
    var activeItems: [DownloadItem] { items.filter { $0.status.isActive } }

    /// Combined progress of everything that hasn't finished yet (queued items count as 0).
    var overallProgress: Double? {
        let pending = items.filter { !$0.status.isDone }
        guard !pending.isEmpty else { return nil }
        let sum = pending.reduce(0.0) { total, item in
            if case .processing = item.status { return total + 1 }
            return total + item.progress
        }
        return sum / Double(pending.count)
    }

    var totalSpeed: Double {
        items.reduce(0) { $0 + (($1.status == .downloading ? $1.speed : nil) ?? 0) }
    }

    func enqueue(url: String, info: MediaInfo?, options: DownloadOptions) {
        let args = YTDLP.downloadArguments(url: url, options: options, formats: info?.formats ?? [], settings: settings)
        let item = DownloadItem(url: url, title: info?.title ?? url, thumbnail: info?.thumbnail, options: options, arguments: args)
        items.insert(item, at: 0)
        if info == nil { resolveMetadata(for: item) }
        pump()
        didChange()
    }

    /// One-step download with the last-used settings (menu bar, clipboard).
    func quickEnqueue(url: String) {
        var o = settings.lastOptions
        o.includePlaylist = false
        o.customFormatID = nil
        enqueue(url: url, info: nil, options: Self.adapted(o, for: url))
    }

    /// Options for a link queued without a preview: no custom stream, and audio for audio-only sites.
    static func adapted(_ options: DownloadOptions, for url: String) -> DownloadOptions {
        var o = options
        if o.mode == .custom { o.mode = .video }
        if MediaSite.match(url)?.audioOnly == true, o.mode != .audio { o.mode = .audio }
        return o
    }

    /// Links queued without a preview (batch, menu bar) get their title and thumbnail
    /// filled in afterwards, one lookup at a time so a big batch doesn't spawn dozens of processes.
    private var metadataChain: Task<Void, Never>?

    private func resolveMetadata(for item: DownloadItem) {
        let previous = metadataChain
        metadataChain = Task { [weak self, weak item] in
            await previous?.value
            guard let self, let item, self.items.contains(where: { $0.id == item.id }) else { return }
            guard let info = try? await YTDLP.fetchInfo(url: item.url, playlist: item.options.includePlaylist, settings: self.settings)
            else { return }
            item.title = info.title
            item.thumbnail = info.thumbnail
            self.saveHistory()
        }
    }

    func cancel(_ item: DownloadItem) {
        if let p = item.process, p.isRunning {
            item.status = .cancelled
            p.interrupt()                       // lets yt-dlp stop ffmpeg cleanly
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if p.isRunning { p.terminate() } }
        } else if !item.status.isDone {
            item.status = .cancelled
        }
        pump()
        didChange()
    }

    func retry(_ item: DownloadItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let copy = DownloadItem(url: item.url, title: item.title, thumbnail: item.thumbnail, options: item.options, arguments: item.arguments)
        items[idx] = copy
        pump()
        didChange()
    }

    func remove(_ item: DownloadItem) {
        if item.status.isActive { cancel(item) }
        items.removeAll { $0.id == item.id }
        didChange()
    }

    func clearFinished() {
        items.removeAll { $0.status.isDone }
        didChange()
    }

    /// Stops every running yt-dlp process immediately (used when quitting). Partial
    /// `.part` files are kept, so Retry after relaunch resumes the download.
    func terminateAllForQuit() {
        for item in items where item.status.isActive {
            item.process?.terminate()
            item.process = nil
            item.status = .failed(Self.interruptedMessage)
        }
        saveHistory()
    }

    func cancelAll() {
        items.filter { !$0.status.isDone }.forEach(cancel)
    }

    private func pump() {
        let slots = max(1, settings.maxConcurrent) - activeCount
        guard slots > 0 else { return }
        // Oldest queued first (items are stored newest-first).
        for item in items.reversed().filter({ $0.status == .queued }).prefix(slots) {
            start(item)
        }
    }

    private func start(_ item: DownloadItem) {
        guard let bin = YTDLP.locate("yt-dlp", override: settings.ytdlpPath) else {
            item.status = .failed(YTDLPError.notInstalled.localizedDescription)
            return
        }
        try? FileManager.default.createDirectory(at: settings.outputDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = item.arguments
        process.environment = YTDLP.environment
        process.standardInput = FileHandle.nullDevice

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        // yt-dlp writes download progress to stdout but postprocessor progress to stderr,
        // so both streams go through the same parser.
        let deliver: (String) -> Void = { [weak self, weak item] line in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let item else { return }
                    self.handle(line: line, for: item)
                }
            }
        }
        let outReader = LineReader(onLine: deliver)
        let errReader = LineReader(onLine: deliver)
        out.fileHandleForReading.readabilityHandler = { h in outReader.feed(h.availableData) }
        err.fileHandleForReading.readabilityHandler = { h in errReader.feed(h.availableData) }

        process.terminationHandler = { [weak self, weak item] p in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            outReader.feed(out.fileHandleForReading.readDataToEndOfFile())
            errReader.feed(err.fileHandleForReading.readDataToEndOfFile())
            outReader.flush()
            errReader.flush()
            let code = p.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let item else { return }
                    self.finish(item, exitCode: code)
                }
            }
        }

        item.process = process
        item.status = .downloading
        item.stage = "Starting…"
        item.appendLog("$ " + YTDLP.shellCommand(item.arguments, binary: bin))
        do {
            try process.run()
        } catch {
            item.status = .failed(error.localizedDescription)
            item.process = nil
        }
    }

    private func handle(line: String, for item: DownloadItem) {
        if line.hasPrefix(YTDLP.progressPrefix) {
            let f = line.dropFirst(YTDLP.progressPrefix.count).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 9 else { return }
            if case .cancelled = item.status { return }
            let downloaded = Double(f[1]) ?? 0
            let total = Double(f[2]) ?? Double(f[3])
            if let total, total > 0 {
                item.progress = min(1, downloaded / total)
                item.totalBytes = Int64(total)
            }
            item.speed = Double(f[4])
            item.eta = Double(f[5]).map { Int($0) }
            item.playlistIndex = Int(f[6])
            item.playlistCount = Int(f[7])
            switch item.options.mode {
            case .audio: item.stage = "Downloading audio"
            case .videoOnly: item.stage = "Downloading video"
            default: item.stage = f[8] == "none" ? "Audio stream" : "Video stream"
            }
            item.status = .downloading
        } else if line.hasPrefix(YTDLP.postprocessPrefix) {
            let f = line.dropFirst(YTDLP.postprocessPrefix.count).split(separator: "|").map(String.init)
            guard f.count >= 2, f[0] == "started" else { return }
            if case .cancelled = item.status { return }
            item.status = .processing(Self.describe(postprocessor: f[1]))
        } else if line.hasPrefix(YTDLP.filePrefix) {
            let path = String(line.dropFirst(YTDLP.filePrefix.count))
            item.outputFiles.append(URL(fileURLWithPath: path))
            item.appendLog("Saved: \(path)")
        } else {
            item.appendLog(line)
        }
    }

    private func finish(_ item: DownloadItem, exitCode: Int32) {
        item.process = nil
        if case .cancelled = item.status {
            // keep
        } else if exitCode == 0 {
            item.status = .finished
            item.progress = 1
            notify(title: "Download complete", body: item.title)
        } else {
            let message = YTDLP.lastError(in: item.log.joined(separator: "\n")) ?? "yt-dlp exited with code \(exitCode)"
            item.status = .failed(YTDLP.explain(message, link: item.url, settings: settings))
            notify(title: "Download failed", body: item.title)
        }
        pump()
        didChange()
        if pendingCount == 0 { NSApp.requestUserAttention(.informationalRequest) }
    }

    // MARK: Persistence & Dock

    static let interruptedMessage = "Interrupted — Retry resumes where it left off"

    private struct Record: Codable {
        var id: UUID
        var createdAt: Date
        var url: String
        var title: String
        var thumbnail: URL?
        var options: DownloadOptions
        var arguments: [String]
        var state: String
        var message: String?
        var files: [String]
    }

    private static var historyURL: URL { AppSettings.supportDirectory.appendingPathComponent("history.json") }

    @ObservationIgnored private var sleepActivity: NSObjectProtocol?

    private func didChange() {
        saveHistory()
        NSApp?.dockTile.badgeLabel = pendingCount > 0 ? "\(pendingCount)" : nil
        updateSleepAssertion()
    }

    /// Keeps the Mac awake (display may still sleep) while something is downloading.
    private func updateSleepAssertion() {
        let needed = settings.preventSleep && pendingCount > 0
        if needed, sleepActivity == nil {
            sleepActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled], reason: "Downloading media")
        } else if !needed, let activity = sleepActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sleepActivity = nil
        }
    }

    private func saveHistory() {
        let records = items.prefix(300).map { item -> Record in
            let (state, message): (String, String?) = {
                switch item.status {
                case .finished: return ("finished", nil)
                case .failed(let m): return ("failed", m)
                case .cancelled: return ("cancelled", nil)
                default: return ("interrupted", nil)   // queued/active items resume as retryable
                }
            }()
            return Record(id: item.id, createdAt: item.createdAt, url: item.url, title: item.title, thumbnail: item.thumbnail,
                          options: item.options, arguments: item.arguments, state: state, message: message,
                          files: item.outputFiles.map(\.path))
        }
        do {
            try FileManager.default.createDirectory(at: Self.historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(records)).write(to: Self.historyURL, options: .atomic)
        } catch {
            NSLog("Grabbit: failed to save history: \(error)")
        }
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Self.historyURL),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return }
        items = records.map { r in
            let item = DownloadItem(id: r.id, createdAt: r.createdAt, url: r.url, title: r.title, thumbnail: r.thumbnail,
                                    options: r.options, arguments: r.arguments)
            item.outputFiles = r.files.map { URL(fileURLWithPath: $0) }
            switch r.state {
            case "finished": item.status = .finished; item.progress = 1
            case "failed": item.status = .failed(r.message ?? "Failed")
            case "cancelled": item.status = .cancelled
            default: item.status = .failed(Self.interruptedMessage)
            }
            return item
        }
    }

    static func describe(postprocessor: String) -> String {
        let p = postprocessor.lowercased()
        if p.contains("merger") { return "Merging audio & video" }
        if p.contains("extractaudio") { return "Converting audio" }
        if p.contains("thumbnailsconvertor") { return "Preparing artwork" }
        if p.contains("embedthumbnail") { return "Embedding artwork" }
        if p.contains("metadata") { return "Writing metadata" }
        if p.contains("subtitle") { return "Embedding subtitles" }
        if p.contains("sponsor") || p.contains("modifychapters") { return "Removing sponsor segments" }
        if p.contains("remux") || p.contains("videoconvertor") { return "Remuxing" }
        if p.contains("movefiles") { return "Finishing up" }
        return postprocessor
    }

    // MARK: Notifications

    static var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestNotificationPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        guard settings.notifyOnFinish, Self.canNotify, !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

extension DownloadItem {
    func appendLog(_ line: String) {
        log.append(line)
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }
}

/// Splits a byte stream into lines (handles `\n` and `\r`). Thread-safe.
final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        var lines: [String] = []
        while let idx = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer[buffer.startIndex..<idx]
            buffer.removeSubrange(buffer.startIndex...idx)
            let line = String(decoding: lineData, as: UTF8.self)
            if !line.isEmpty { lines.append(line) }
        }
        lock.unlock()
        lines.forEach(onLine)
    }

    func flush() {
        lock.lock()
        let rest = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll()
        lock.unlock()
        if !rest.isEmpty { onLine(rest) }
    }
}
