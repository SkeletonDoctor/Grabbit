import CryptoKit
import Foundation
import Observation

/// Downloads yt-dlp and ffmpeg/ffprobe into ~/Library/Application Support/YTDown/bin,
/// verifying each file against the publisher's SHA-256 checksum before installing it.
@MainActor
@Observable
final class ToolInstaller {
    enum Tool: String, CaseIterable, Identifiable {
        case ytdlp = "yt-dlp", ffmpeg, ffprobe
        var id: String { rawValue }
    }

    enum Phase: Equatable {
        case idle
        case downloading(Tool, Double)
        case verifying(Tool)
        case done
        case failed(String)
    }

    static let shared = ToolInstaller()

    var phase: Phase = .idle
    /// Bumped after every install so views re-check which tools are present.
    var revision = 0

    var isBusy: Bool {
        switch phase {
        case .downloading, .verifying: return true
        default: return false
        }
    }

    static var binDirectory: URL {
        AppSettings.supportDirectory.appendingPathComponent("bin", isDirectory: true)
    }

    static func isManaged(_ path: String) -> Bool { path.hasPrefix(binDirectory.path) }

    private static var ffmpegArch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "amd64"
        #endif
    }

    /// Installs the given tools (defaults to whichever are missing).
    func install(_ tools: [Tool]) async {
        guard !isBusy, !tools.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: Self.binDirectory, withIntermediateDirectories: true)
            for tool in tools {
                switch tool {
                case .ytdlp: try await installYTDLP()
                case .ffmpeg, .ffprobe: try await installFFmpegTool(tool)
                }
            }
            phase = .done
        } catch {
            phase = .failed(error.localizedDescription)
        }
        revision += 1
    }

    func missingTools(settings: AppSettings) -> [Tool] {
        var missing: [Tool] = []
        if YTDLP.locate("yt-dlp", override: settings.ytdlpPath) == nil { missing.append(.ytdlp) }
        if YTDLP.locate("ffmpeg", override: settings.ffmpegPath) == nil { missing.append(.ffmpeg) }
        if YTDLP.locate("ffprobe") == nil { missing.append(.ffprobe) }
        return missing
    }

    /// Set when a background refresh actually installed a newer yt-dlp; shown once as a toast.
    var updateNote: String?

    /// YouTube changes often and old yt-dlp builds stop working, so yt-dlp is refreshed in the
    /// background at most every three days: a copy installed by the app updates itself
    /// (yt-dlp's own verified `-U`), a Homebrew copy goes through `brew upgrade yt-dlp`.
    /// Anything at a custom path is left alone.
    func refreshYTDLPIfStale(settings: AppSettings) {
        guard settings.autoUpdateTools,
              let bin = YTDLP.locate("yt-dlp", override: settings.ytdlpPath) else { return }
        let command: (String, [String])
        if Self.isManaged(bin) {
            command = (bin, ["-U"])
        } else if bin.hasPrefix("/opt/homebrew/") || bin.hasPrefix("/usr/local/"), let brew = YTDLP.locate("brew") {
            command = (brew, ["upgrade", "yt-dlp"])
        } else {
            return
        }
        let key = "ytdlpLastSelfUpdate"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 3 * 24 * 60 * 60 else { return }
        UserDefaults.standard.set(Date(), forKey: key)
        Task {
            let before = await YTDLP.version(settings: settings)
            // Keep the old Homebrew version on disk so a download already running isn't cut off.
            _ = try? await YTDLP.run(command.0, command.1, extraEnvironment: ["HOMEBREW_NO_INSTALL_CLEANUP": "1"])
            let after = await YTDLP.version(settings: settings)
            if let after, let before, after != before { updateNote = "yt-dlp updated to \(after)" }
            revision += 1
        }
    }

    // MARK: yt-dlp

    private func installYTDLP() async throws {
        let base = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/"
        phase = .downloading(.ytdlp, 0)
        let sums = try await fetchText(URL(string: base + "SHA2-256SUMS")!)
        guard let expected = sums.split(separator: "\n")
            .first(where: { $0.hasSuffix("  yt-dlp_macos") })?
            .split(separator: " ").first.map(String.init)
        else { throw InstallError("Couldn't read yt-dlp's published checksums.") }

        let file = try await download(URL(string: base + "yt-dlp_macos")!, tool: .ytdlp)
        phase = .verifying(.ytdlp)
        try verify(file, expected: expected)
        try place(file, as: "yt-dlp")
    }

    // MARK: ffmpeg / ffprobe (static builds by Martin Riedl, linked from ffmpeg.org)

    private func installFFmpegTool(_ tool: Tool) async throws {
        let redirect = URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(Self.ffmpegArch)/release/\(tool.rawValue).zip")!
        phase = .downloading(tool, 0)
        let (zip, finalURL) = try await downloadResolving(redirect, tool: tool)
        let sumText = try await fetchText(URL(string: finalURL.absoluteString + ".sha256")!)
        guard let expected = sumText.split(whereSeparator: \.isWhitespace).first.map(String.init) else {
            throw InstallError("Couldn't read the \(tool.rawValue) checksum.")
        }
        phase = .verifying(tool)
        try verify(zip, expected: expected)

        let unzipDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: unzipDir) }
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unzipDir.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw InstallError("Couldn't unzip \(tool.rawValue).") }

        let enumerator = FileManager.default.enumerator(at: unzipDir, includingPropertiesForKeys: nil)
        guard let binary = (enumerator?.allObjects as? [URL])?.first(where: { $0.lastPathComponent == tool.rawValue }) else {
            throw InstallError("\(tool.rawValue) wasn't found inside the download.")
        }
        try place(binary, as: tool.rawValue)
    }

    // MARK: Helpers

    private func place(_ file: URL, as name: String) throws {
        let dest = Self.binDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: file, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        // Clear quarantine so Gatekeeper doesn't block the helper when yt-dlp launches it.
        removexattr(dest.path, "com.apple.quarantine", 0)
    }

    private func verify(_ file: URL, expected: String) throws {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual.lowercased() == expected.lowercased() else {
            try? FileManager.default.removeItem(at: file)
            throw InstallError("Checksum mismatch — the download was discarded for safety.")
        }
    }

    private func fetchText(_ url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw InstallError("Couldn't reach \(url.host ?? "server").") }
        return String(decoding: data, as: UTF8.self)
    }

    private func download(_ url: URL, tool: Tool) async throws -> URL {
        try await downloadResolving(url, tool: tool).0
    }

    /// Downloads with live progress; returns the local file and the final (post-redirect) URL.
    private func downloadResolving(_ url: URL, tool: Tool) async throws -> (URL, URL) {
        try await withCheckedThrowingContinuation { cont in
            var observation: NSKeyValueObservation?
            let task = URLSession.shared.downloadTask(with: url) { tmp, response, error in
                observation?.invalidate()
                if let error { cont.resume(throwing: error); return }
                guard let tmp, let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    cont.resume(throwing: InstallError("Download of \(tool.rawValue) failed.")); return
                }
                // The temp file is deleted when this handler returns, so move it first.
                let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + tool.rawValue)
                do {
                    try FileManager.default.moveItem(at: tmp, to: keep)
                    cont.resume(returning: (keep, http.url ?? url))
                } catch {
                    cont.resume(throwing: error)
                }
            }
            observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let value = progress.fractionCompleted
                Task { @MainActor in
                    // Ignore late progress callbacks once we've moved on to verifying.
                    if case .downloading(let current, _) = self.phase, current == tool {
                        self.phase = .downloading(tool, value)
                    }
                }
            }
            task.resume()
        }
    }
}

struct InstallError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
