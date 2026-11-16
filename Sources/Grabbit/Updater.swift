import AppKit
import CryptoKit
import Foundation
import Observation

/// Self-update from GitHub Releases.
///
/// Each release carries `Grabbit.zip` and `Grabbit.zip.sig` (an Ed25519 signature made with the
/// maintainer's private key, see Scripts/sign_update.swift). The app downloads the archive,
/// verifies the signature against the public key below, stages the new bundle, and swaps it in
/// on restart or the next quit. Nothing unsigned is ever installed.
@MainActor
@Observable
final class Updater {
    /// The GitHub repository releases are pulled from. Forks: change this and `publicKey`.
    nonisolated static let repository = "SkeletonDoctor/Grabbit"
    nonisolated static let publicKey = "FhOSVm4rPUfNnyDIVA4vdeHsNjes0hEQuYEyQ+HA+GA="
    nonisolated static let archiveName = "Grabbit.zip"

    static var releasesPage: URL { URL(string: "https://github.com/\(repository)/releases")! }

    struct Release: Equatable {
        let version: String
        let notes: String
        let page: URL
        let archive: URL
        let signature: URL
    }

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Release, Double)
        case ready(Release)
        case failed(String)
    }

    static let shared = Updater()

    var phase: Phase = .idle
    var lastChecked: Date? = UserDefaults.standard.object(forKey: "updateLastChecked") as? Date

    @ObservationIgnored private var settings: AppSettings?
    @ObservationIgnored private var stagedApp: URL?
    @ObservationIgnored private var relaunchOnQuit = false
    @ObservationIgnored private var schedule: Task<Void, Never>?

    // MARK: Environment

    static var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Why this copy can't replace itself, or nil when it can.
    static var installBlocker: String? {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app", currentVersion != nil else {
            return "This is a development build."
        }
        if bundle.path.contains("/AppTranslocation/") {
            return "Move Grabbit to the Applications folder and reopen it to enable automatic updates."
        }
        if !FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path) {
            return "Grabbit can't write to \(bundle.deletingLastPathComponent().path)."
        }
        return nil
    }

    private nonisolated static var stagingDirectory: URL { AppSettings.supportDirectory.appendingPathComponent("update", isDirectory: true) }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading: return true
        default: return false
        }
    }

    // MARK: Rename from YTDown

    /// Copies that updated from the old name are still sitting in a bundle called YTDown.app.
    /// Rename the bundle in place and reopen it, so Finder, the Dock and Spotlight show "Grabbit".
    /// Returns true if the app is about to relaunch.
    static func adoptNewBundleNameIfNeeded() -> Bool {
        let fm = FileManager.default
        let bundle = Bundle.main.bundleURL
        let target = bundle.deletingLastPathComponent().appendingPathComponent("Grabbit.app")
        guard bundle.lastPathComponent == "YTDown.app", installBlocker == nil,
              !fm.fileExists(atPath: target.path),
              (try? fm.moveItem(at: bundle, to: target)) != nil
        else { return false }
        relaunch(at: target)
        return true
    }

    /// Opens `app` as soon as this process has exited.
    private static func relaunch(at app: URL) {
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$0\"",
                            app.path]
        try? waiter.run()
    }

    // MARK: Scheduling

    /// Checks shortly after launch and then once a day while the app stays open.
    func start(settings: AppSettings) {
        self.settings = settings
        try? FileManager.default.removeItem(at: Self.stagingDirectory)   // leftovers from a previous run
        guard Self.currentVersion != nil else { return }
        schedule = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            while !Task.isCancelled {
                if let self, self.settings?.autoCheckUpdates == true, !self.isBusy, self.stagedApp == nil {
                    await self.check(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
    }

    // MARK: Checking

    func check(userInitiated: Bool) async {
        guard !isBusy else { return }
        if case .ready = phase { return }
        phase = .checking
        do {
            let release = try await latestRelease()
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: "updateLastChecked")
            guard let release, Self.isVersion(release.version, newerThan: Self.currentVersion ?? "0") else {
                phase = .upToDate
                return
            }
            phase = .available(release)
            if settings?.autoInstallUpdates == true, Self.installBlocker == nil {
                await download(release)
            }
        } catch {
            // Background checks fail silently (offline, rate limit); only report when the user asked.
            phase = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    private func latestRelease() async throws -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }   // no releases published yet
        guard status == 200 else { throw InstallError("GitHub didn't answer the update check (HTTP \(status)).") }

        struct Payload: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String
            let body: String?
            let html_url: URL
            let assets: [Asset]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let archive = payload.assets.first(where: { $0.name == Self.archiveName }),
              let signature = payload.assets.first(where: { $0.name == Self.archiveName + ".sig" })
        else { return nil }   // a release without a signed build isn't installable
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        return Release(version: version, notes: payload.body ?? "", page: payload.html_url,
                       archive: archive.browser_download_url, signature: signature.browser_download_url)
    }

    /// Numeric, component-wise comparison: 1.10 > 1.9, 1.2 == 1.2.0.
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 } }
        let (x, y) = (parts(a), parts(b))
        for i in 0..<max(x.count, y.count) {
            let (l, r) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if l != r { return l > r }
        }
        return false
    }

    // MARK: Downloading & verifying

    func download(_ release: Release) async {
        if let blocker = Self.installBlocker { phase = .failed(blocker); return }
        phase = .downloading(release, 0)
        do {
            let fm = FileManager.default
            try? fm.removeItem(at: Self.stagingDirectory)
            try fm.createDirectory(at: Self.stagingDirectory, withIntermediateDirectories: true)

            let zip = try await fetchArchive(release)
            defer { try? fm.removeItem(at: zip) }
            let (sigData, _) = try await URLSession.shared.data(from: release.signature)
            try Self.verify(archive: zip, signature: sigData)

            let unpacked = Self.stagingDirectory.appendingPathComponent("unpacked", isDirectory: true)
            try Self.runTool("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
            guard let app = (try? fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil))?
                    .first(where: { $0.pathExtension == "app" }),
                  let staged = Bundle(url: app),
                  staged.bundleIdentifier == Bundle.main.bundleIdentifier,
                  let stagedVersion = staged.infoDictionary?["CFBundleShortVersionString"] as? String,
                  Self.isVersion(stagedVersion, newerThan: Self.currentVersion ?? "0")
            else { throw InstallError("The downloaded update isn't a newer copy of Grabbit.") }
            try? Self.runTool("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])

            stagedApp = app
            phase = .ready(release)
        } catch {
            try? FileManager.default.removeItem(at: Self.stagingDirectory)
            phase = .failed(error.localizedDescription)
        }
    }

    private func fetchArchive(_ release: Release) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            var observation: NSKeyValueObservation?
            let task = URLSession.shared.downloadTask(with: release.archive) { tmp, response, error in
                observation?.invalidate()
                if let error { cont.resume(throwing: error); return }
                guard let tmp, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    cont.resume(throwing: InstallError("Couldn't download the update.")); return
                }
                let keep = Self.stagingDirectory.appendingPathComponent(Self.archiveName)
                do {
                    try FileManager.default.moveItem(at: tmp, to: keep)
                    cont.resume(returning: keep)
                } catch {
                    cont.resume(throwing: error)
                }
            }
            observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let value = progress.fractionCompleted
                Task { @MainActor in
                    if case .downloading(let r, _) = self.phase { self.phase = .downloading(r, value) }
                }
            }
            task.resume()
        }
    }

    nonisolated static func verify(archive: URL, signature: Data) throws {
        let text = String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sig = Data(base64Encoded: text),
              let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let data = try? Data(contentsOf: archive, options: .mappedIfSafe),
              key.isValidSignature(sig, for: data)
        else { throw InstallError("The update's signature didn't verify, so it was discarded.") }
    }

    private nonisolated static func runTool(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw InstallError("\((path as NSString).lastPathComponent) failed while unpacking the update.") }
    }

    // MARK: Installing

    /// Quits (asking about running downloads as usual), swaps the bundle and reopens the app.
    func installAndRelaunch() {
        guard stagedApp != nil else { return }
        relaunchOnQuit = true
        NSApp.terminate(nil)
    }

    /// The user declined to quit — keep the staged update for later.
    func quitWasCancelled() { relaunchOnQuit = false }

    /// Called once quitting is certain: installs a staged update, if there is one.
    func finishOnQuit() {
        guard let staged = stagedApp, Self.installBlocker == nil else { return }
        let fm = FileManager.default
        let current = Bundle.main.bundleURL
        let old = Self.stagingDirectory.appendingPathComponent("previous.app")
        do {
            try? fm.removeItem(at: old)
            try fm.moveItem(at: current, to: old)
            do {
                try fm.moveItem(at: staged, to: current)
            } catch {
                try? fm.moveItem(at: old, to: current)   // put the running version back
                throw error
            }
        } catch {
            NSLog("Grabbit: update install failed: \(error)")
            return
        }
        stagedApp = nil
        try? fm.removeItem(at: Self.stagingDirectory)
        if relaunchOnQuit { Self.relaunch(at: current) }
    }
}
