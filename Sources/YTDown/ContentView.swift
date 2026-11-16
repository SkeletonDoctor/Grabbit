import SwiftUI

struct ContentView: View {
    @Environment(DownloadManager.self) private var manager
    @State private var showQueue = true

    var body: some View {
        ComposerView(showQueue: $showQueue)
            .background(Backdrop())
            .hiddenToolbarBackground()
            .inspector(isPresented: $showQueue) {
                QueueView()
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
