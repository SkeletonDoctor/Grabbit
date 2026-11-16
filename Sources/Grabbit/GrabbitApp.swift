import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var manager: DownloadManager?
    @MainActor static var settings: AppSettings?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Updater.adoptNewBundleNameIfNeeded() { exit(0) }
        // Needed when launched via `swift run` (no bundle) so the window gets focus and a Dock icon.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DownloadManager.requestNotificationPermission()
        if let settings = Self.settings {
            Updater.shared.start(settings: settings)
            ToolInstaller.shared.refreshYTDLPIfStale(settings: settings)
        }
    }

    /// With the menu bar item on, closing the window leaves the app (and its downloads) running.
    @MainActor
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(Self.settings?.showMenuBarIcon ?? false)
    }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let manager = Self.manager else { return .terminateNow }
        let active = manager.activeCount
        if active > 0 {
            let alert = NSAlert()
            alert.messageText = active == 1 ? "A download is in progress" : "\(active) downloads are in progress"
            alert.informativeText = "If you quit now, they'll stop. You can resume them next time with Retry."
            alert.addButton(withTitle: "Keep Downloading")
            alert.addButton(withTitle: "Quit Anyway")
            if alert.runModal() == .alertFirstButtonReturn {
                Updater.shared.quitWasCancelled()
                return .terminateCancel
            }
        }
        manager.terminateAllForQuit()
        Updater.shared.finishOnQuit()
        return .terminateNow
    }
}

@main
struct GrabbitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var settings: AppSettings
    @State private var manager: DownloadManager

    init() {
        let s = AppSettings()
        _settings = State(initialValue: s)
        let m = DownloadManager(settings: s)
        _manager = State(initialValue: m)
        AppDelegate.manager = m
        AppDelegate.settings = s
    }

    var body: some Scene {
        Window("Grabbit", id: "main") {
            ContentView()
                .environment(settings)
                .environment(manager)
                .frame(minWidth: 880, minHeight: 620)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await Updater.shared.check(userInitiated: true) }
                }
                .disabled(Updater.shared.isBusy)
            }
        }

        MenuBarExtra(isInserted: $settings.showMenuBarIcon) {
            MenuBarView()
                .environment(settings)
                .environment(manager)
        } label: {
            Image(systemName: manager.activeCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}
