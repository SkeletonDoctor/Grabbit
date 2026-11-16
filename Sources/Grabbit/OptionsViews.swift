import SwiftUI

// MARK: - Mode tiles

struct ModePicker: View {
    @Binding var mode: DownloadMode
    var customAvailable: Bool
    /// False for audio-only sources, where the video modes can't produce anything.
    var videoAvailable = true
    @Namespace private var ns

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "What do you want?")
            GlassGroup(spacing: 14) {
                HStack(spacing: 12) {
                    ForEach(DownloadMode.allCases) { m in tile(m) }
                }
            }
        }
    }

    private func tile(_ m: DownloadMode) -> some View {
        let selected = mode == m
        let needsVideo = m == .video || m == .videoOnly
        let enabled = (m != .custom || customAvailable) && (!needsVideo || videoAvailable)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { mode = m }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: m.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.red))
                    .frame(width: 40, height: 40)
                    .glass(Circle(), tint: selected ? .white.opacity(0.25) : nil)
                    .symbolEffect(.bounce, value: selected)
                Text(m.rawValue)
                    .font(.headline)
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                Text(needsVideo && !videoAvailable ? "This link is audio only"
                     : m == .custom && !customAvailable ? "Fetch a link first to see its formats" : m.subtitle)
                    .font(.caption)
                    .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .glass(shape, tint: selected ? Color.red.opacity(0.8) : nil, interactive: true)
        .scaleEffect(selected ? 1.0 : 0.98)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

// MARK: - Format options

struct OptionsPanel: View {
    @Binding var options: DownloadOptions
    let info: MediaInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Format")
            Group {
                switch options.mode {
                case .video, .videoOnly: videoOptions
                case .audio: audioOptions
                case .custom: customOptions
                }
            }
            .card()
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: options.mode)
        }
    }

    private var qualities: [VideoQuality] {
        guard let top = info?.availableHeights.first else { return VideoQuality.allCases }
        // Show every tier up to the one that contains the source's top resolution.
        let ceiling = VideoQuality.allCases.filter { $0 != .best && $0.rawValue >= top }.map(\.rawValue).min() ?? top
        return VideoQuality.allCases.filter { $0 == .best || $0.rawValue <= ceiling }
    }

    private var videoOptions: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 16) {
            GridRow {
                label("Quality", "4k.tv")
                GlassMenuPicker(options: qualities, selection: $options.quality, icon: "sparkles.tv") { $0.label }
                    .frame(maxWidth: 260)
            }
            GridRow {
                label("Container", "shippingbox")
                GlassSegmented(options: VideoContainer.allCases, selection: $options.container) { $0.rawValue.uppercased() }
            }
            GridRow(alignment: .top) {
                label("Compatibility", "checkmark.seal")
                VStack(alignment: .leading, spacing: 6) {
                    GlassChip(title: "Prefer H.264 / AAC", symbol: "play.rectangle", isOn: $options.preferH264)
                    Text(options.preferH264
                         ? "Plays everywhere (QuickTime, iPhone, Final Cut). YouTube only offers H.264 up to 1080p."
                         : "Best quality may use VP9 or AV1, which QuickTime can't always play. MKV is the safest container for these.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if options.mode == .video {
                GridRow {
                    label("Audio", "speaker.wave.2")
                    Text("Best audio track is merged automatically with ffmpeg.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var audioOptions: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 16) {
            GridRow {
                label("Format", "music.note")
                GlassSegmented(options: AudioFormat.allCases, selection: $options.audioFormat) {
                    $0 == .best ? "Original" : $0.rawValue.uppercased()
                }
            }
            GridRow {
                label("Bitrate", "dial.medium")
                GlassMenuPicker(options: AudioBitrate.allCases, selection: $options.audioBitrate, icon: "waveform") { $0.label }
                    .frame(maxWidth: 220)
                    .disabled(!options.audioFormat.isLossy)
                    .opacity(options.audioFormat.isLossy ? 1 : 0.45)
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text(audioHint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var audioHint: String {
        switch options.audioFormat {
        case .mp3: return "MP3 works on every device. 320 kbps is the highest MP3 bitrate."
        case .m4a: return "AAC in M4A — great for Apple Music & iPhone. Often no re-encode needed."
        case .opus: return "Opus is YouTube's native audio codec — smallest files, excellent quality."
        case .flac: return "Lossless container. Note: YouTube's source audio is lossy, so this won't add quality."
        case .wav: return "Uncompressed PCM — large files, ideal for editing in a DAW."
        case .best: return "Keeps YouTube's original audio stream without re-encoding."
        }
    }

    @ViewBuilder
    private var customOptions: some View {
        if let info, !info.formats.isEmpty {
            FormatList(formats: info.formats, selection: $options.customFormatID, container: $options.container)
        } else {
            Text("Fetch a video to list its available formats.").foregroundStyle(.secondary)
        }
    }

    private func label(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .fontWeight(.medium)
            .frame(width: 130, alignment: .leading)
    }
}

// MARK: - Custom format list

private struct FormatList: View {
    enum Filter: String, CaseIterable, Sendable { case all = "All", video = "Video", audio = "Audio" }

    let formats: [MediaFormat]
    @Binding var selection: String?
    @Binding var container: VideoContainer
    @State private var filter: Filter = .all

    private var rows: [MediaFormat] {
        formats.reversed().filter {
            switch filter {
            case .all: return true
            case .video: return $0.hasVideo
            case .audio: return !$0.hasVideo && $0.hasAudio
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pick an exact stream. Video-only streams are merged with the best audio.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                GlassSegmented(options: Filter.allCases, selection: $filter) { $0.rawValue }
            }
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(rows) { f in row(f) }
                }
                .padding(4)
            }
            .frame(height: 300)
            HStack(spacing: 12) {
                Label("Merge into", systemImage: "shippingbox").fontWeight(.medium)
                GlassSegmented(options: VideoContainer.allCases, selection: $container) { $0.rawValue.uppercased() }
            }
        }
    }

    private func row(_ f: MediaFormat) -> some View {
        let selected = selection == f.id
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = f.id }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: f.hasVideo ? (f.hasAudio ? "film" : "video") : "waveform")
                    .frame(width: 22)
                Text(f.resolutionLabel).fontWeight(.semibold).frame(width: 80, alignment: .leading)
                Text(f.kindLabel).frame(width: 100, alignment: .leading)
                Text(f.ext.uppercased()).frame(width: 50, alignment: .leading)
                Text(f.shortCodec).frame(minWidth: 90, alignment: .leading)
                Spacer()
                Text(f.filesize.map(formatBytes) ?? "—").monospacedDigit().frame(width: 80, alignment: .trailing)
                Text(f.tbr.map { "\(Int($0)) kbps" } ?? "—").monospacedDigit().frame(width: 80, alignment: .trailing)
                Text(f.id).font(.caption.monospaced()).frame(width: 44, alignment: .trailing)
                    .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
            }
            .font(.callout)
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glass(Capsule(), tint: selected ? Color.red.opacity(0.8) : nil, interactive: true)
    }
}

// MARK: - Extras

struct ExtrasPanel: View {
    @Binding var options: DownloadOptions
    /// SponsorBlock only has data for YouTube.
    var sponsorAvailable = true
    @State private var expanded = false

    private var isVideo: Bool { options.mode != .audio }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { expanded.toggle() }
            } label: {
                HStack {
                    SectionHeader(title: "Extras")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Spacer()
                    if !expanded {
                        Text(activeSummary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 16) {
                    GlassGroup(spacing: 10) {
                        FlowLayout(spacing: 10) {
                            GlassChip(title: "Cover art", symbol: "photo", isOn: $options.embedThumbnail)
                            GlassChip(title: "Metadata", symbol: "tag", isOn: $options.embedMetadata)
                            GlassChip(title: "Chapters", symbol: "list.bullet.indent", isOn: $options.embedChapters)
                                .disabled(!isVideo)
                            GlassChip(title: "Skip sponsors", symbol: "forward.end", isOn: $options.sponsorBlock)
                                .disabled(!sponsorAvailable)
                                .help(sponsorAvailable ? "Cut sponsor segments using SponsorBlock" : "SponsorBlock only works for YouTube")
                            GlassChip(title: "Subtitles", symbol: "captions.bubble", isOn: $options.subtitles)
                                .disabled(!isVideo)
                            GlassChip(title: "Trim", symbol: "scissors", isOn: $options.trimEnabled)
                        }
                    }

                    if options.subtitles && isVideo {
                        HStack(spacing: 10) {
                            Label("Languages", systemImage: "globe").fontWeight(.medium)
                            GlassField(placeholder: "en.*", text: $options.subtitleLangs, width: 150)
                                .help("Comma separated, regex allowed — e.g. en.*,es,fr")
                            GlassChip(title: "Auto-generated", symbol: "wand.and.stars", isOn: $options.autoSubs)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if options.trimEnabled {
                        HStack(spacing: 10) {
                            Label("Section", systemImage: "timeline.selection").fontWeight(.medium)
                            GlassField(placeholder: "Start", text: $options.trimStart, width: 100, monospaced: true)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            GlassField(placeholder: "End", text: $options.trimEnd, width: 100, monospaced: true)
                            Text("HH:MM:SS").font(.caption).foregroundStyle(.secondary)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .card()
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
    }

    private var activeSummary: String {
        var parts: [String] = []
        if options.embedThumbnail { parts.append("Artwork") }
        if options.embedMetadata { parts.append("Metadata") }
        if options.embedChapters && isVideo { parts.append("Chapters") }
        if options.subtitles && isVideo { parts.append("Subtitles") }
        if options.sponsorBlock { parts.append("SponsorBlock") }
        if options.trimEnabled { parts.append("Trim \(options.trimStart)–\(options.trimEnd)") }
        return parts.isEmpty ? "None" : parts.joined(separator: " · ")
    }
}

/// Wraps chips onto new lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(i)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
