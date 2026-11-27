import SwiftUI

struct ContentView: View {
    @Environment(DownloadManager.self) private var manager
    @Environment(Player.self) private var player
    @State private var showQueue = true
    @State private var tab = SidebarTab.downloads

    enum SidebarTab: String, CaseIterable { case downloads = "Downloads", nowPlaying = "Now Playing" }

    var body: some View {
        ComposerView(showQueue: $showQueue)
            .background(Backdrop())
            .hiddenToolbarBackground()
            .onChange(of: player.url) { _, url in
                if url != nil { tab = .nowPlaying; showQueue = true }
            }
            .inspector(isPresented: $showQueue) {
                VStack(spacing: 0) {
                    GlassSegmented(options: SidebarTab.allCases, selection: $tab, title: \.rawValue)
                        .padding(.top, 12)
                    switch tab {
                    case .downloads: QueueView()
                    case .nowPlaying: NowPlayingView()
                    }
                }
                    .background {
                        // Same colorful mesh, frosted, so the queue reads as a glass sidebar.
                        Backdrop().overlay(.ultraThinMaterial).ignoresSafeArea()
                    }
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { showQueue.toggle() }
                    } label: {
                        Label("Downloads", systemImage: "arrow.down.circle")
                            .overlay(alignment: .topTrailing) {
                                if manager.pendingCount > 0 {
                                    Text("\(manager.pendingCount)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(.red, in: Capsule())
                                        .offset(x: 8, y: -6)
                                }
                            }
                    }
                    .help("Show or hide the download queue")
                    .keyboardShortcut("j", modifiers: [.command])
                }
            }
    }
}
