import Foundation

enum YTDLPError: LocalizedError {
    case notInstalled
    case badOutput(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "yt-dlp was not found. Install it with `brew install yt-dlp ffmpeg`, or set its path in Settings."
        case .badOutput(let msg), .failed(let msg):
            return msg
        }
    }
}

/// Locating the binaries and building yt-dlp invocations.
enum YTDLP {
    /// GUI apps don't inherit the shell PATH, so look in the usual install locations.
    static let searchDirectories: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Tools installed from inside the app live in Application Support and are checked last,
        // so an existing Homebrew install always wins.
        let managed = AppSettings.supportDirectory.appendingPathComponent("bin").path
        return ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/bin", "/opt/local/bin", "/usr/bin", managed]
    }()

    static func locate(_ name: String, override: String? = nil) -> String? {
        if let override, !override.isEmpty, FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        for dir in searchDirectories {
            let path = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existing = env["PATH"] ?? ""
        env["PATH"] = (searchDirectories + [existing]).joined(separator: ":")
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        env["LC_ALL"] = "en_US.UTF-8"
        return env
    }

    // MARK: Running one-shot commands

    struct Output {
        let status: Int32
        let stdout: Data
        let stderr: String
    }

    static func run(_ executable: String, _ args: [String], extraEnvironment: [String: String] = [:]) async throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.environment = environment.merging(extraEnvironment) { _, new in new }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Output, Error>) in
                do { try process.run() } catch { cont.resume(throwing: error); return }
                DispatchQueue.global(qos: .userInitiated).async {
                    // Drain both pipes concurrently so a large JSON blob can't deadlock the child.
                    var errData = Data()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        errData = err.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    let outData = out.fileHandleForReading.readDataToEndOfFile()
                    group.wait()
                    process.waitUntilExit()
                    cont.resume(returning: Output(
                        status: process.terminationStatus,
                        stdout: outData,
                        stderr: String(decoding: errData, as: UTF8.self)
                    ))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    static func fetchInfo(url: String, playlist: Bool, settings: AppSettings) async throws -> MediaInfo {
        guard let bin = locate("yt-dlp", override: settings.ytdlpPath) else { throw YTDLPError.notInstalled }
        var args = ["-J", "--flat-playlist", "--no-warnings", playlist ? "--yes-playlist" : "--no-playlist"]
        args += cookieArgs(settings)
        args.append(url)
        let result = try await run(bin, args)
        guard result.status == 0 else {
            throw YTDLPError.failed(lastError(in: result.stderr) ?? "yt-dlp exited with code \(result.status)")
        }
        return try MediaInfo.parse(result.stdout)
    }

    static func version(settings: AppSettings) async -> String? {
        guard let bin = locate("yt-dlp", override: settings.ytdlpPath),
              let out = try? await run(bin, ["--version"]), out.status == 0 else { return nil }
        return String(decoding: out.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pulls every http(s) link out of arbitrary pasted text.
    static func extractURLs(from text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen = Set<String>()
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            let s = url.absoluteString
            return seen.insert(s).inserted ? s : nil
        }
    }

    static func lastError(in text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        if let err = lines.last(where: { $0.hasPrefix("ERROR:") }) {
            return err.replacingOccurrences(of: "ERROR: ", with: "")
        }
        return lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    static func cookieArgs(_ settings: AppSettings) -> [String] {
        settings.cookieBrowser == .none ? [] : ["--cookies-from-browser", settings.cookieBrowser.rawValue]
    }

    // MARK: Building a download command

    static let progressPrefix = "YTDP|"
    static let postprocessPrefix = "YTPP|"
    static let filePrefix = "YTFILE|"

    static func downloadArguments(url: String, options o: DownloadOptions, formats: [MediaFormat], settings: AppSettings) -> [String] {
        var a: [String] = []

        // Machine-readable progress on stdout
        a += ["--newline", "--progress", "--quiet", "--no-warnings", "--no-mtime"]
        a += ["--progress-template",
              "download:\(progressPrefix)%(progress.status)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s|%(info.playlist_index)s|%(info.n_entries)s|%(info.vcodec)s"]
        a += ["--progress-template", "postprocess:\(postprocessPrefix)%(progress.status)s|%(progress.postprocessor)s"]
        a += ["--print", "after_move:\(filePrefix)%(filepath)s"]

        if let ffmpeg = locate("ffmpeg", override: settings.ffmpegPath) {
            a += ["--ffmpeg-location", ffmpeg]
        }

        let heightFilter = o.quality == .best ? "" : "[height<=\(o.quality.rawValue)]"
        var isVideo = true
        var thumbnailOK = true

        switch o.mode {
        case .video:
            a += ["-f", heightFilter.isEmpty ? "bv*+ba/b" : "bv*\(heightFilter)+ba/b\(heightFilter)/bv*+ba/b"]
            a += ["--merge-output-format", o.container.rawValue]
            a += sortArgs(for: o)
            thumbnailOK = o.container != .webm

        case .videoOnly:
            a += ["-f", heightFilter.isEmpty ? "bv*/b" : "bv*\(heightFilter)/bv*/b"]
            a += ["--remux-video", o.container.rawValue]
            a += sortArgs(for: o)
            thumbnailOK = o.container != .webm

        case .audio:
            isVideo = false
            switch o.audioFormat {
            case .m4a: a += ["-f", "ba[ext=m4a]/ba/b"]
            case .opus: a += ["-f", "ba[acodec=opus]/ba/b"]
            default: a += ["-f", "ba/b"]
            }
            a += ["-x"]
            if o.audioFormat != .best {
                a += ["--audio-format", o.audioFormat.rawValue]
            }
            if o.audioFormat.isLossy {
                a += ["--audio-quality", o.audioBitrate.rawValue]
            }
            thumbnailOK = ![.wav, .best].contains(o.audioFormat)

        case .custom:
            let fid = o.customFormatID ?? "b"
            let fmt = formats.first { $0.id == fid }
            if let fmt, fmt.hasVideo, !fmt.hasAudio {
                a += ["-f", "\(fid)+ba/\(fid)"]
                a += ["--merge-output-format", o.container.rawValue]
            } else if let fmt, !fmt.hasVideo {
                isVideo = false
                a += ["-f", fid]
            } else {
                a += ["-f", fid]
            }
            thumbnailOK = fmt.map { !["webm", "wav"].contains($0.ext) } ?? false
        }

        if o.embedMetadata { a.append("--embed-metadata") }
        if o.embedThumbnail && thumbnailOK {
            a += ["--embed-thumbnail", "--convert-thumbnails", "jpg"]
        }
        if isVideo {
            if o.embedChapters { a.append("--embed-chapters") }
            if o.subtitles {
                a += ["--write-subs", "--sub-langs", o.subtitleLangs.isEmpty ? "en.*" : o.subtitleLangs, "--embed-subs"]
                a += ["--compat-options", "no-keep-subs"]   // don't leave .vtt files next to the video
                if o.autoSubs { a.append("--write-auto-subs") }
            }
        }
        if o.sponsorBlock {
            a += ["--sponsorblock-remove", "sponsor,selfpromo,interaction"]
        }
        if o.trimEnabled {
            a += ["--download-sections", "*\(o.trimStart)-\(o.trimEnd)", "--force-keyframes-at-cuts"]
        }

        a += cookieArgs(settings)
        let limit = settings.rateLimit.trimmingCharacters(in: .whitespaces)
        if !limit.isEmpty { a += ["--limit-rate", limit] }
        a.append(o.includePlaylist ? "--yes-playlist" : "--no-playlist")

        a += ["-P", settings.outputDirectory.path]
        let template = o.includePlaylist ? settings.playlistTemplate : settings.filenameTemplate
        a += ["-o", template]

        a += ["--", url]
        return a
    }

    private static func sortArgs(for o: DownloadOptions) -> [String] {
        if o.preferH264 { return ["-S", "vcodec:h264,res,acodec:m4a"] }
        if o.container == .webm { return ["-S", "vcodec:vp9,acodec:opus"] }
        return []
    }

    /// A copy-pasteable shell rendering of the command.
    static func shellCommand(_ args: [String], binary: String = "yt-dlp") -> String {
        ([binary] + args).map { arg in
            let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./=:,+"))
            if !arg.isEmpty && arg.unicodeScalars.allSatisfy(safe.contains) { return arg }
            return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }
}
