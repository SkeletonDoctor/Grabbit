import SwiftUI

/// The sites Grabbit knows by name. yt-dlp handles well over a thousand; this list only decides
/// which copied links get offered automatically, how a download is labelled, and a few
/// per-site defaults. Any other link still works when pasted.
struct MediaSite: Identifiable, Equatable {
    let name: String
    let symbol: String
    let tint: Color
    let hosts: [String]
    /// The site only carries audio, so video modes make no sense for it.
    var audioOnly = false
    /// Most content needs a signed-in browser session.
    var usuallyNeedsLogin = false

    var id: String { name }

    static let catalog: [MediaSite] = [
        MediaSite(name: "YouTube", symbol: "play.rectangle.fill", tint: Color(red: 1.0, green: 0.20, blue: 0.20),
                  hosts: ["youtube.com", "youtu.be", "youtube-nocookie.com"]),
        MediaSite(name: "TikTok", symbol: "music.note", tint: Color(red: 0.10, green: 0.85, blue: 0.85),
                  hosts: ["tiktok.com"]),
        MediaSite(name: "Instagram", symbol: "camera.fill", tint: Color(red: 0.88, green: 0.19, blue: 0.55),
                  hosts: ["instagram.com"], usuallyNeedsLogin: true),
        MediaSite(name: "SoundCloud", symbol: "cloud.fill", tint: Color(red: 1.0, green: 0.45, blue: 0.0),
                  hosts: ["soundcloud.com"], audioOnly: true),
        MediaSite(name: "X", symbol: "bubble.left.fill", tint: Color(white: 0.55),
                  hosts: ["x.com", "twitter.com"]),
        MediaSite(name: "Facebook", symbol: "person.2.fill", tint: Color(red: 0.10, green: 0.47, blue: 0.95),
                  hosts: ["facebook.com", "fb.watch"]),
        MediaSite(name: "Twitch", symbol: "gamecontroller.fill", tint: Color(red: 0.57, green: 0.27, blue: 1.0),
                  hosts: ["twitch.tv"]),
        MediaSite(name: "Vimeo", symbol: "play.circle.fill", tint: Color(red: 0.10, green: 0.72, blue: 0.92),
                  hosts: ["vimeo.com"]),
        MediaSite(name: "Reddit", symbol: "text.bubble.fill", tint: Color(red: 1.0, green: 0.27, blue: 0.0),
                  hosts: ["reddit.com", "redd.it"]),
        MediaSite(name: "Bandcamp", symbol: "opticaldisc.fill", tint: Color(red: 0.11, green: 0.63, blue: 0.76),
                  hosts: ["bandcamp.com"], audioOnly: true),
        MediaSite(name: "Mixcloud", symbol: "waveform", tint: Color(red: 0.36, green: 0.30, blue: 0.95),
                  hosts: ["mixcloud.com"], audioOnly: true),
        MediaSite(name: "Dailymotion", symbol: "play.tv.fill", tint: Color(red: 0.0, green: 0.52, blue: 0.95),
                  hosts: ["dailymotion.com", "dai.ly"]),
        MediaSite(name: "Bilibili", symbol: "tv.fill", tint: Color(red: 0.0, green: 0.68, blue: 0.93),
                  hosts: ["bilibili.com", "b23.tv"]),
        MediaSite(name: "Kick", symbol: "bolt.fill", tint: Color(red: 0.33, green: 0.90, blue: 0.10),
                  hosts: ["kick.com"]),
        MediaSite(name: "Rumble", symbol: "play.square.fill", tint: Color(red: 0.52, green: 0.78, blue: 0.20),
                  hosts: ["rumble.com"]),
        MediaSite(name: "Threads", symbol: "at", tint: Color(white: 0.55),
                  hosts: ["threads.net", "threads.com"], usuallyNeedsLogin: true),
        MediaSite(name: "Pinterest", symbol: "pin.fill", tint: Color(red: 0.90, green: 0.0, blue: 0.14),
                  hosts: ["pinterest.com", "pin.it"]),
        MediaSite(name: "LinkedIn", symbol: "briefcase.fill", tint: Color(red: 0.04, green: 0.40, blue: 0.76),
                  hosts: ["linkedin.com"]),
        MediaSite(name: "Tumblr", symbol: "square.text.square.fill", tint: Color(red: 0.21, green: 0.27, blue: 0.36),
                  hosts: ["tumblr.com"]),
        MediaSite(name: "Snapchat", symbol: "bell.fill", tint: Color(red: 0.95, green: 0.85, blue: 0.0),
                  hosts: ["snapchat.com"]),
        MediaSite(name: "Bluesky", symbol: "cloud.sun.fill", tint: Color(red: 0.07, green: 0.52, blue: 1.0),
                  hosts: ["bsky.app"]),
        MediaSite(name: "Streamable", symbol: "play.fill", tint: Color(red: 0.06, green: 0.56, blue: 0.98),
                  hosts: ["streamable.com"]),
        MediaSite(name: "Odysee", symbol: "sparkles", tint: Color(red: 0.94, green: 0.20, blue: 0.40),
                  hosts: ["odysee.com"]),
        MediaSite(name: "TED", symbol: "person.wave.2.fill", tint: Color(red: 0.90, green: 0.17, blue: 0.12),
                  hosts: ["ted.com"]),
    ]

    /// The headline sites, for places with room for only a few names.
    static var featured: [MediaSite] { Array(catalog.prefix(8)) }

    /// The known site a link belongs to, matched on the real host (so "box.com" isn't "x.com").
    static func match(_ link: String) -> MediaSite? {
        guard let host = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased() else { return nil }
        return catalog.first { site in
            site.hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }

    /// A display name for any link: the known site, or a tidied-up host ("vk.com").
    static func displayName(for link: String) -> String? {
        if let site = match(link) { return site.name }
        guard let host = URL(string: link)?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A small tinted capsule naming the site a link comes from.
struct SiteBadge: View {
    let link: String
    var compact = false

    var body: some View {
        if let name = MediaSite.displayName(for: link) {
            let site = MediaSite.match(link)
            HStack(spacing: 4) {
                Image(systemName: site?.symbol ?? "globe")
                Text(name)
            }
            .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 3)
            .background((site?.tint ?? Color.gray).opacity(0.9), in: Capsule())
        }
    }
}
