import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct NowPlayingView: View {
    @Environment(Player.self) private var player

    var body: some View {
        if let url = player.url {
            VStack(spacing: 18) {
                if UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true {
                    Image(systemName: "music.note")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    VideoPlayer(player: player.avPlayer)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Text(player.title)
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                GlassGroup(spacing: 12) {
                    HStack(spacing: 12) {
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .frame(width: 54, height: 54)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glass(Circle(), tint: .red.opacity(0.85), interactive: true)
                        .help(player.isPlaying ? "Pause" : "Play")

                        Button { player.stop() } label: {
                            Image(systemName: "stop.fill")
                                .font(.callout.weight(.semibold))
                                .frame(width: 38, height: 38)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glass(Circle(), interactive: true)
                        .help("Stop")
                    }
                }
                Spacer()
            }
            .padding(16)
        } else {
            ContentUnavailableView {
                Label("Nothing playing", systemImage: "play.circle")
            } description: {
                Text("Press play on a finished download to listen or watch it here.")
            }
            .frame(maxHeight: .infinity)
        }
    }
}
