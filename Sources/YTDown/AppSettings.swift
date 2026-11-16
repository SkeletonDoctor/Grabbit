import Foundation
import Observation

@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var outputDirectory: URL {
        didSet { defaults.set(outputDirectory.path, forKey: "outputDirectory") }
    }
    var filenameTemplate: String {
        didSet { defaults.set(filenameTemplate, forKey: "filenameTemplate") }
    }
    var playlistTemplate: String {
        didSet { defaults.set(playlistTemplate, forKey: "playlistTemplate") }
    }
    var maxConcurrent: Int {
        didSet { defaults.set(maxConcurrent, forKey: "maxConcurrent") }
    }
    var cookieBrowser: CookieBrowser {
        didSet { defaults.set(cookieBrowser.rawValue, forKey: "cookieBrowser") }
    }
    var ytdlpPath: String {
        didSet { defaults.set(ytdlpPath, forKey: "ytdlpPath") }
    }
    var ffmpegPath: String {
        didSet { defaults.set(ffmpegPath, forKey: "ffmpegPath") }
    }
    var notifyOnFinish: Bool {
        didSet { defaults.set(notifyOnFinish, forKey: "notifyOnFinish") }
    }
    var autoFetchOnPaste: Bool {
        didSet { defaults.set(autoFetchOnPaste, forKey: "autoFetchOnPaste") }
    }
    /// yt-dlp --limit-rate value, e.g. "5M" or "500K". Empty = unlimited.
    var rateLimit: String {
        didSet { defaults.set(rateLimit, forKey: "rateLimit") }
    }
    /// Show a menu bar item; while it's shown, closing the window keeps the app (and downloads) running.
    var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }
    var preventSleep: Bool {
        didSet { defaults.set(preventSleep, forKey: "preventSleep") }
    }
    var backdropStyle: BackdropStyle {
        didSet { defaults.set(backdropStyle.rawValue, forKey: "backdropStyle") }
    }
    var animateBackdrop: Bool {
        didSet { defaults.set(animateBackdrop, forKey: "animateBackdrop") }
    }
    var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: "autoCheckUpdates") }
    }
    var autoInstallUpdates: Bool {
        didSet { defaults.set(autoInstallUpdates, forKey: "autoInstallUpdates") }
    }
    /// Refresh yt-dlp in the background (app-installed or Homebrew) every few days.
    var autoUpdateTools: Bool {
        didSet { defaults.set(autoUpdateTools, forKey: "autoUpdateTools") }
    }
    var lastOptions: DownloadOptions {
        didSet {
            if let data = try? JSONEncoder().encode(lastOptions) { defaults.set(data, forKey: "lastOptions") }
        }
    }

    /// Where history, managed tools and staged updates live. `YTDOWN_SUPPORT_DIR` overrides it (testing).
    static let supportDirectory: URL = {
        if let custom = ProcessInfo.processInfo.environment["YTDOWN_SUPPORT_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YTDown", isDirectory: true)
    }()

    static let defaultTemplate = "%(title)s [%(id)s].%(ext)s"
    static let defaultPlaylistTemplate = "%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s"

    init() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        outputDirectory = defaults.string(forKey: "outputDirectory").map { URL(fileURLWithPath: $0) } ?? downloads
        filenameTemplate = defaults.string(forKey: "filenameTemplate") ?? Self.defaultTemplate
        playlistTemplate = defaults.string(forKey: "playlistTemplate") ?? Self.defaultPlaylistTemplate
        let mc = defaults.integer(forKey: "maxConcurrent")
        maxConcurrent = mc == 0 ? 2 : mc
        cookieBrowser = CookieBrowser(rawValue: defaults.string(forKey: "cookieBrowser") ?? "") ?? .none
        ytdlpPath = defaults.string(forKey: "ytdlpPath") ?? ""
        ffmpegPath = defaults.string(forKey: "ffmpegPath") ?? ""
        notifyOnFinish = defaults.object(forKey: "notifyOnFinish") as? Bool ?? true
        autoFetchOnPaste = defaults.object(forKey: "autoFetchOnPaste") as? Bool ?? true
        rateLimit = defaults.string(forKey: "rateLimit") ?? ""
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        preventSleep = defaults.object(forKey: "preventSleep") as? Bool ?? true
        backdropStyle = BackdropStyle(rawValue: defaults.string(forKey: "backdropStyle") ?? "") ?? .aurora
        animateBackdrop = defaults.object(forKey: "animateBackdrop") as? Bool ?? true
        autoUpdateTools = defaults.object(forKey: "autoUpdateTools") as? Bool ?? true
        autoCheckUpdates = defaults.object(forKey: "autoCheckUpdates") as? Bool ?? true
        autoInstallUpdates = defaults.object(forKey: "autoInstallUpdates") as? Bool ?? true
        if let data = defaults.data(forKey: "lastOptions"),
           let opts = try? JSONDecoder().decode(DownloadOptions.self, from: data) {
            lastOptions = opts
        } else {
            lastOptions = DownloadOptions()
        }
    }
}
