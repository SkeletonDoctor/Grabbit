import AppKit
import SwiftUI

/// The menu bar popover: what's downloading right now, plus one-click download of a copied link.
struct MenuBarView: View {
    @Environment(DownloadManager.self) private var manager
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var copiedLink: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Grabbit").font(.headline)
                Spacer()
                Text(statusText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let overall = manager.overallProgress {
                GlassProgressBar(value: overall, tint: .red)
            }

            if manager.activeItems.isEmpty {
                Label(manager.pendingCount > 0 ? "Waiting to start…" : "Nothing downloading",
                      systemImage: manager.pendingCount > 0 ? "clock" : "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(manager.activeItems.prefix(4)) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.callout).lineLimit(1)
                            HStack(spacing: 8) {
                                if case .processing(let what) = item.status {
                                    GlassProgressBar(value: nil, tint: .purple)
                                    Text(what).font(.caption2).foregroundStyle(.secondary).fixedSize()
                                } else {
                                    GlassProgressBar(value: item.progress, tint: .red)
                                    Text("\(Int(item.progress * 100))%")
                                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                        .frame(width: 30, alignment: .trailing)
                                }
                            }
                        }
                    }
                    if manager.activeItems.count > 4 {
                        Text("and \(manager.activeItems.count - 4) more…").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()

            if let copiedLink {
                row("Download Copied Link", symbol: "sparkles", detail: MediaSite.displayName(for: copiedLink)) {
                    manager.quickEnqueue(url: copiedLink)
                    self.copiedLink = nil
                }
            }
            row("Open Grabbit", symbol: "macwindow") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                dismiss()
            }
            row("Open Download Folder", symbol: "folder") {
                NSWorkspace.shared.open(settings.outputDirectory)
                dismiss()
            }
            row("Quit Grabbit", symbol: "power") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { copiedLink = Self.linkOnClipboard() }
    }

    private var statusText: String {
        guard manager.pendingCount > 0 else { return "Idle" }
        let speed = manager.totalSpeed
        let count = "\(manager.pendingCount) pending"
        return speed > 0 ? "\(count) · \(formatBytes(Int64(speed)))/s" : count
    }

    private func row(_ title: String, symbol: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        MenuRow(title: title, symbol: symbol, detail: detail, action: action)
    }

    static func linkOnClipboard() -> String? {
        guard let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              s.count < 500, !s.contains(where: \.isWhitespace),
              let u = URL(string: s), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.host != nil
        else { return nil }
        return s
    }
}

private struct MenuRow: View {
    let title: String
    let symbol: String
    let detail: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 18)
                Text(title)
                Spacer()
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
