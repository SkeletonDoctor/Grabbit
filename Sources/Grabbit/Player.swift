import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

/// One in-app player shared by every view, so Now Playing can pause what a download row started.
@MainActor @Observable
final class Player {
    private(set) var url: URL?
    private(set) var title = ""
    private(set) var source = ""
    private(set) var artwork: URL?
    private(set) var isAudio = false
    private(set) var isPlaying = false
    /// Seconds into the current file, and its length (0 until known).
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    @ObservationIgnored let avPlayer = AVPlayer()
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeObserver: Any?
    /// Bumped on every play request, so a slow load can tell it has been overtaken by a newer one.
    @ObservationIgnored private var request = 0

    init() {
        // Track the real state so pausing from the video's own controls keeps our buttons in sync.
        statusObservation = avPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            let playing = p.timeControlStatus != .paused
            Task { @MainActor in self?.isPlaying = playing }
        }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
    }

    private func tick(_ time: CMTime) {
        guard url != nil else { return }
        if time.seconds.isFinite { position = time.seconds }
        if let d = avPlayer.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
    }

    func play(_ file: URL, title: String, source: String = "", artwork: URL? = nil) {
        request += 1
        let mine = request
        Task {
            // AVFoundation can't play webm/mkv, which yt-dlp often produces; hand those to the default app.
            let playable = (try? await AVURLAsset(url: file).load(.isPlayable)) == true
            guard mine == request else { return }   // the user has already picked something else
            guard playable else {
                avPlayer.pause()
                NSWorkspace.shared.open(file)
                return
            }
            avPlayer.replaceCurrentItem(with: AVPlayerItem(url: file))
            url = file
            self.title = title
            self.source = source
            self.artwork = artwork
            isAudio = UTType(filenameExtension: file.pathExtension)?.conforms(to: .audio) == true
            position = 0
            duration = 0
            avPlayer.play()
        }
    }

    func toggle() {
        if isPlaying { avPlayer.pause(); return }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { stop(); return }
        if let item = avPlayer.currentItem, item.currentTime() >= item.duration {
            avPlayer.seek(to: .zero) // finished: play again from the start
        }
        avPlayer.play()
    }

    func pause() { avPlayer.pause() }

    func seek(to seconds: Double) {
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        position = target
        avPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skip(_ seconds: Double) { seek(to: position + seconds) }

    /// Pauses here and hands the file to the default app (a bigger window, or a format we can't play).
    func openInDefaultApp() {
        guard let url else { return }
        avPlayer.pause()
        NSWorkspace.shared.open(url)
    }

    func stop() {
        request += 1
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        url = nil
        title = ""
        source = ""
        artwork = nil
        position = 0
        duration = 0
    }
}
