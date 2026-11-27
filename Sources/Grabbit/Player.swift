import AppKit
import AVFoundation
import Observation

/// One in-app player shared by every view, so Now Playing can pause what a download row started.
@MainActor @Observable
final class Player {
    private(set) var url: URL?
    private(set) var title = ""
    private(set) var isPlaying = false
    @ObservationIgnored let avPlayer = AVPlayer()
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    init() {
        // Track the real state so pausing from the video's own controls keeps our buttons in sync.
        statusObservation = avPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            let playing = p.timeControlStatus != .paused
            Task { @MainActor in self?.isPlaying = playing }
        }
    }

    func play(_ file: URL, title: String) {
        Task {
            // AVFoundation can't play webm/mkv/opus, which yt-dlp often produces; hand those to the default app.
            guard (try? await AVURLAsset(url: file).load(.isPlayable)) == true else {
                NSWorkspace.shared.open(file)
                return
            }
            avPlayer.replaceCurrentItem(with: AVPlayerItem(url: file))
            url = file
            self.title = title
            avPlayer.play()
        }
    }

    func toggle() {
        if isPlaying { avPlayer.pause(); return }
        if let item = avPlayer.currentItem, item.currentTime() >= item.duration {
            avPlayer.seek(to: .zero) // finished: play again from the start
        }
        avPlayer.play()
    }

    func stop() {
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        url = nil
        title = ""
    }
}
