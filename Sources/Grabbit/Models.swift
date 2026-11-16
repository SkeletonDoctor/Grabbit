import Foundation

// MARK: - Metadata returned by `yt-dlp -J`

struct MediaFormat: Identifiable, Hashable {
    let id: String          // format_id
    let ext: String
    let height: Int?
    let fps: Double?
    let vcodec: String?
    let acodec: String?
    let abr: Double?
    let tbr: Double?
    let filesize: Int64?
    let note: String?

    var hasVideo: Bool { (vcodec ?? "none") != "none" }
    var hasAudio: Bool { (acodec ?? "none") != "none" }

    var kindLabel: String {
        switch (hasVideo, hasAudio) {
        case (true, true): return "Video + Audio"
        case (true, false): return "Video only"
        case (false, true): return "Audio only"
        default: return "Other"
        }
    }

    var shortCodec: String {
        func short(_ c: String?) -> String? {
            guard let c, c != "none" else { return nil }
            let lower = c.lowercased()
            if lower.hasPrefix("avc1") || lower.hasPrefix("h264") { return "H.264" }
            if lower.hasPrefix("vp09") || lower.hasPrefix("vp9") { return "VP9" }
            if lower.hasPrefix("av01") { return "AV1" }
            if lower.hasPrefix("hev1") || lower.hasPrefix("hvc1") { return "HEVC" }
            if lower.hasPrefix("mp4a") { return "AAC" }
            if lower.hasPrefix("opus") { return "Opus" }
            return c.components(separatedBy: ".").first
        }
        return [short(vcodec), short(acodec)].compactMap { $0 }.joined(separator: " / ")
    }

    var resolutionLabel: String {
        if let height, hasVideo {
            let f = (fps ?? 0) > 30 ? "\(Int(fps!))" : ""
            return "\(height)p\(f)"
        }
        if let abr { return "\(Int(abr)) kbps" }
        return note ?? "—"
    }
}

struct MediaInfo: Identifiable {
    let id: String
    let title: String
    let uploader: String?
    let duration: Double?
    let thumbnail: URL?
    let viewCount: Int?
    let isPlaylist: Bool
    let entryCount: Int
    let formats: [MediaFormat]
    /// The page this media lives on (falls back to the link that was fetched).
    var pageURL: String = ""

    /// True when there is nothing to see, only to hear (SoundCloud, Bandcamp, podcasts…).
    var isAudioOnly: Bool {
        if !formats.isEmpty { return !formats.contains(where: \.hasVideo) }
        return MediaSite.match(pageURL)?.audioOnly ?? false
    }

    var availableHeights: [Int] {
        Array(Set(formats.filter(\.hasVideo).compactMap(\.height))).sorted(by: >)
    }

    var durationText: String? { duration.map(formatDuration) }

    /// Rough output size for the chosen options, from yt-dlp's reported (or approximate) stream sizes.
    func estimatedSize(for o: DownloadOptions) -> Int64? {
        guard !isPlaylist else { return nil }
        func size(_ f: MediaFormat) -> Int64? {
            if let s = f.filesize { return s }
            if let tbr = f.tbr, let duration { return Int64(tbr * 1000 / 8 * duration) }
            return nil
        }
        let bestAudio = formats.filter { $0.hasAudio && !$0.hasVideo }.compactMap(size).max() ?? 0
        let cap = o.quality == .best ? Int.max : o.quality.rawValue
        var videos = formats.filter { $0.hasVideo && ($0.height ?? 0) <= cap }
        if o.preferH264 {
            let h264 = videos.filter { ($0.vcodec ?? "").hasPrefix("avc1") }
            if !h264.isEmpty { videos = h264 }
        }
        let topHeight = videos.compactMap(\.height).max()
        let bestVideo = videos.filter { $0.height == topHeight }.compactMap(size).max()

        var total: Int64?
        switch o.mode {
        case .video: total = bestVideo.map { $0 + bestAudio }
        case .videoOnly: total = bestVideo
        case .audio:
            if let duration, o.audioFormat.isLossy, o.audioFormat != .opus, let kbps = Double(o.audioBitrate.rawValue.dropLast()) {
                total = Int64(kbps * 1000 / 8 * duration)
            } else if let duration, o.audioFormat == .wav || o.audioFormat == .flac {
                total = Int64(1411.2 * 1000 / 8 * duration * (o.audioFormat == .flac ? 0.6 : 1))
            } else {
                total = bestAudio > 0 ? bestAudio : nil
            }
        case .custom:
            guard let f = formats.first(where: { $0.id == o.customFormatID }) else { return nil }
            total = size(f).map { $0 + (f.hasAudio ? 0 : bestAudio) }
        }
        if let t = total, o.trimEnabled, let duration, duration > 0,
           let start = parseTimestamp(o.trimStart), let end = parseTimestamp(o.trimEnd), end > start {
            total = Int64(Double(t) * min(1, (end - start) / duration))
        }
        return total.flatMap { $0 > 0 ? $0 : nil }
    }

    static func parse(_ data: Data) throws -> MediaInfo {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTDLPError.badOutput("Unexpected JSON from yt-dlp")
        }
        let type = obj["_type"] as? String
        let entries = obj["entries"] as? [[String: Any]] ?? []
        let isPlaylist = type == "playlist"

        var thumb = (obj["thumbnail"] as? String).flatMap(URL.init(string:))
        if thumb == nil, let thumbs = obj["thumbnails"] as? [[String: Any]],
           let last = thumbs.last?["url"] as? String {
            thumb = URL(string: last)
        }
        if thumb == nil, isPlaylist, let first = entries.first,
           let thumbs = first["thumbnails"] as? [[String: Any]],
           let last = thumbs.last?["url"] as? String {
            thumb = URL(string: last)
        }

        let formats: [MediaFormat] = (obj["formats"] as? [[String: Any]] ?? []).compactMap { f in
            guard let id = f["format_id"] as? String else { return nil }
            // Skip storyboard / image-only formats
            if (f["vcodec"] as? String) == "none" && (f["acodec"] as? String) == "none" { return nil }
            if (f["ext"] as? String) == "mhtml" { return nil }
            let size = (f["filesize"] as? NSNumber)?.int64Value ?? (f["filesize_approx"] as? NSNumber)?.int64Value
            return MediaFormat(
                id: id,
                ext: f["ext"] as? String ?? "?",
                height: (f["height"] as? NSNumber)?.intValue,
                fps: (f["fps"] as? NSNumber)?.doubleValue,
                vcodec: f["vcodec"] as? String,
                acodec: f["acodec"] as? String,
                abr: (f["abr"] as? NSNumber)?.doubleValue,
                tbr: (f["tbr"] as? NSNumber)?.doubleValue,
                filesize: size,
                note: f["format_note"] as? String
            )
        }

        return MediaInfo(
            id: obj["id"] as? String ?? UUID().uuidString,
            title: obj["title"] as? String ?? "Untitled",
            uploader: (obj["uploader"] as? String) ?? (obj["channel"] as? String) ?? (obj["creator"] as? String),
            duration: (obj["duration"] as? NSNumber)?.doubleValue,
            thumbnail: thumb,
            viewCount: (obj["view_count"] as? NSNumber)?.intValue,
            isPlaylist: isPlaylist,
            entryCount: (obj["playlist_count"] as? Int) ?? entries.count,
            formats: formats,
            pageURL: (obj["webpage_url"] as? String) ?? (obj["original_url"] as? String) ?? ""
        )
    }
}

// MARK: - Download options

enum DownloadMode: String, CaseIterable, Identifiable, Codable {
    case video = "Video"
    case audio = "Audio"
    case videoOnly = "Video Only"
    case custom = "Custom"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        case .videoOnly: return "video.slash"
        case .custom: return "slider.horizontal.3"
        }
    }

    var subtitle: String {
        switch self {
        case .video: return "Best video merged with best audio"
        case .audio: return "Extract audio track only"
        case .videoOnly: return "Silent video stream, no audio"
        case .custom: return "Pick an exact format from the list"
        }
    }
}

enum VideoQuality: Int, CaseIterable, Identifiable, Codable {
    case best = 0, p4320 = 4320, p2160 = 2160, p1440 = 1440, p1080 = 1080, p720 = 720, p480 = 480, p360 = 360, p240 = 240
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .best: return "Best available"
        case .p4320: return "8K (4320p)"
        case .p2160: return "4K (2160p)"
        case .p1440: return "1440p"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .p360: return "360p"
        case .p240: return "240p"
        }
    }
}

enum VideoContainer: String, CaseIterable, Identifiable, Codable {
    case mp4, mkv, webm, mov
    var id: String { rawValue }
}

enum AudioFormat: String, CaseIterable, Identifiable, Codable {
    case mp3, m4a, opus, flac, wav, best
    var id: String { rawValue }
    var label: String { self == .best ? "Original (no re-encode)" : rawValue.uppercased() }
    var isLossy: Bool { [.mp3, .m4a, .opus].contains(self) }
}

enum AudioBitrate: String, CaseIterable, Identifiable, Codable {
    case best = "0", k320 = "320K", k256 = "256K", k192 = "192K", k128 = "128K"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .best: return "Best (VBR)"
        default: return rawValue.replacingOccurrences(of: "K", with: " kbps")
        }
    }
}

enum CookieBrowser: String, CaseIterable, Identifiable, Codable {
    case none, safari, chrome, firefox, brave, edge, arc = "chromium"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Don't use cookies"
        case .arc: return "Chromium"
        default: return rawValue.capitalized
        }
    }
}

struct DownloadOptions: Codable, Equatable {
    var mode: DownloadMode = .video
    var quality: VideoQuality = .best
    var container: VideoContainer = .mp4
    var preferH264: Bool = false
    var audioFormat: AudioFormat = .mp3
    var audioBitrate: AudioBitrate = .k320
    var customFormatID: String? = nil

    var embedThumbnail: Bool = true
    var embedMetadata: Bool = true
    var embedChapters: Bool = true
    var subtitles: Bool = false
    var subtitleLangs: String = "en.*"
    var autoSubs: Bool = false
    var sponsorBlock: Bool = false

    var trimEnabled: Bool = false
    var trimStart: String = "00:00:00"
    var trimEnd: String = "00:01:00"

    var includePlaylist: Bool = false
}

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

func parseTimestamp(_ text: String) -> Double? {
    let parts = text.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
    return parts.reduce(0) { $0 * 60 + $1! }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
