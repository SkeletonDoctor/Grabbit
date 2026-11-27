import AVKit
import SwiftUI

struct NowPlayingView: View {
    @Environment(Player.self) private var player
    /// Where the seek bar thumb is while it is being dragged; nil when it just follows playback.
    @State private var scrub: Double?

    var body: some View {
        if let url = player.url {
            ScrollView {
                VStack(spacing: 18) {
                    stage
                    VStack(spacing: 4) {
                        Text(player.title)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        Text(subtitle(for: url))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    seekBar
                    transport
                    secondaryActions(url)
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            ContentUnavailableView {
                Label("Nothing playing", systemImage: "play.circle")
            } description: {
                Text("Press play on a finished download to listen or watch it here.")
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func subtitle(for url: URL) -> String {
        [player.source, url.pathExtension.uppercased()].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Artwork or video

    @ViewBuilder
    private var stage: some View {
        if player.isAudio {
            artwork
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                .scaleEffect(player.isPlaying ? 1 : 0.92)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: player.isPlaying)
                .padding(.top, 8)
        } else {
            VideoSurface(player: player.avPlayer)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
        }
    }

    private var artwork: some View {
        AsyncImage(url: player.artwork) { phase in
            if case .success(let image) = phase {
                // Cover art is usually a wide video thumbnail: fill the square and crop the sides.
                Color.clear.overlay(image.resizable().aspectRatio(contentMode: .fill))
            } else {
                brandGradient.overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 64, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9)))
            }
        }
    }

    // MARK: Seek bar

    private var seekBar: some View {
        let length = max(player.duration, 0.1)
        let shown = scrub ?? min(player.position, length)
        return VStack(spacing: 2) {
            Slider(value: Binding(get: { shown }, set: { scrub = $0 }), in: 0...length) { editing in
                if !editing, let scrub {
                    player.seek(to: scrub)
                    self.scrub = nil
                }
            }
            .controlSize(.small)
            .tint(.red)
            .disabled(player.duration <= 0)
            HStack {
                Text(Self.clock(shown))
                Spacer()
                Text(player.duration > 0 ? "-" + Self.clock(player.duration - shown) : "--:--")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: Buttons

    private var transport: some View {
        GlassGroup(spacing: 14) {
            HStack(spacing: 14) {
                roundButton("gobackward.15", size: 40, help: "Back 15 seconds") { player.skip(-15) }
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 58, height: 58)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glass(Circle(), tint: .red.opacity(0.85), interactive: true)
                .help(player.isPlaying ? "Pause" : "Play")
                roundButton("goforward.15", size: 40, help: "Forward 15 seconds") { player.skip(15) }
            }
        }
    }

    private func secondaryActions(_ url: URL) -> some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                pill("Open in Default App", symbol: "arrow.up.forward.app") { player.openInDefaultApp() }
                roundButton("magnifyingglass", size: 30, help: "Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                roundButton("stop.fill", size: 30, help: "Stop and close") { player.stop() }
            }
        }
    }

    private func roundButton(_ symbol: String, size: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(size > 34 ? .title3 : .caption.weight(.semibold))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glass(Circle(), interactive: true)
        .help(help)
    }

    private func pill(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glass(Capsule(), interactive: true)
    }
}

/// AppKit's player view: unlike SwiftUI's `VideoPlayer` it can offer a full-screen button, which
/// matters here because the sidebar is narrow.
private struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        // The system bar only shows while the pointer is over the video; it adds volume and full screen
        // to the always-visible controls below.
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
