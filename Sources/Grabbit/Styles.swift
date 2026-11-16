import SwiftUI

// MARK: - Liquid Glass primitives
// Real Liquid Glass on macOS 26+, a close material-based approximation on macOS 14–15.

extension View {
    /// Liquid Glass in any shape, optionally tinted and/or reacting to pointer interaction.
    @ViewBuilder
    func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint.opacity(0.35)) }
                }
            }
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                                 startPoint: .top, endPoint: .bottom)))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
    }

    /// Ties a glass shape to an identity so it morphs fluidly between positions inside a `GlassGroup`.
    @ViewBuilder
    func glassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self.matchedGeometryEffect(id: id, in: namespace)
        }
    }

    /// A rounded glass content card.
    func card(cornerRadius: CGFloat = 24, padding: CGFloat = 18, tint: Color? = nil) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint)
    }

    func glassBar(cornerRadius: CGFloat = 16, interactive: Bool = false) -> some View {
        glass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: interactive)
    }

    /// Primary action: a capsule of tinted Liquid Glass (the same material as the selected tiles and chips).
    func prominentGlassButton(tint: Color = .red) -> some View {
        self.buttonStyle(TintedGlassButtonStyle(tint: tint))
    }

    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Lets the backdrop run up under the title bar (macOS 15+).
    @ViewBuilder
    func hiddenToolbarBackground() -> some View {
        if #available(macOS 15.0, *) {
            self.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
    }

    /// Soft blur where content scrolls under the transparent title bar (macOS 26+).
    @ViewBuilder
    func softTopEdge() -> some View {
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    /// Round glass icon button.
    func glassCircleButton() -> some View {
        self.glassButton().buttonBorderShape(.circle)
    }
}

struct TintedGlassButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        TintedGlassButton(configuration: configuration, tint: tint)
    }

    private struct TintedGlassButton: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Capsule())
                .glass(Capsule(),
                       tint: isEnabled ? tint.opacity(configuration.isPressed ? 1 : (hovering ? 0.9 : 0.8)) : Color.gray.opacity(0.35),
                       interactive: isEnabled)
                .shadow(color: isEnabled ? tint.opacity(hovering ? 0.45 : 0.3) : .clear, radius: hovering ? 12 : 8, y: 3)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// Groups glass shapes so they blend and morph into each other (GlassEffectContainer on macOS 26+).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Controls

/// A glass pull-down menu that replaces the stock pop-up button.
struct GlassMenuPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    var icon: String? = nil
    let title: (Value) -> String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.snappy) { selection = option }
                } label: {
                    if option == selection {
                        Label(title(option), systemImage: "checkmark")
                    } else {
                        Text(title(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).foregroundStyle(.secondary)
                }
                Text(title(selection))
                    .fontWeight(.medium)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glass(Capsule(), interactive: true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Segmented control whose selection is a sliding, morphing drop of tinted glass.
struct GlassSegmented<Value: Hashable & Sendable>: View {
    let options: [Value]
    @Binding var selection: Value
    var tint: Color = .red
    let title: (Value) -> String
    @Namespace private var ns
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GlassGroup(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { option in
                    let selected = option == selection
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { selection = option }
                    } label: {
                        Text(title(option))
                            .font(.callout.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .frame(minWidth: 56)
                            .contentShape(Capsule())
                            .background {
                                if selected {
                                    Color.clear
                                        .glass(Capsule(), tint: tint.opacity(isEnabled ? 0.85 : 0.3), interactive: true)
                                        .glassID("selection", in: ns)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .glass(Capsule())
        }
        .fixedSize()
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// A capsule toggle made of glass that lights up (tints) when on.
struct GlassChip: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool
    var tint: Color = .red
    @Environment(\.isEnabled) private var isEnabled

    /// A disabled chip never looks "on", even if its stored value is.
    private var lit: Bool { isOn && isEnabled }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isOn.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: lit ? "checkmark.circle.fill" : symbol)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(lit ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glass(Capsule(), tint: lit ? tint.opacity(0.85) : nil, interactive: true)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// A plain text field sitting in a glass capsule.
struct GlassField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat? = nil
    var monospaced = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(monospaced ? .body.monospacedDigit() : .body)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(width: width)
            .glass(Capsule())
    }
}

struct SectionHeader: View {
    let title: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .tracking(0.6)
        .padding(.leading, 6)
    }
}

// MARK: - Brand mark

/// Grabbit's mark: a download arrow whose stem is a pair of rabbit ears, on a tray line.
/// Same geometry as the app icon (Scripts/make_icon.swift).
struct GrabbitMark: Shape {
    func path(in rect: CGRect) -> Path {
        let u = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - u / 2, y: rect.midY - u / 2)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * u, y: origin.y + y * u) }
        var path = Path()
        for (cx, degrees) in [(CGFloat(0.40), CGFloat(-7)), (0.60, 7)] {
            let w = 0.13 * u, h = 0.44 * u
            let ear = Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: w / 2)
            let c = pt(cx, 0.31)
            path.addPath(ear, transform: CGAffineTransform(translationX: c.x, y: c.y).rotated(by: degrees * .pi / 180))
        }
        var head = Path()
        head.move(to: pt(0.25, 0.50)); head.addLine(to: pt(0.75, 0.50)); head.addLine(to: pt(0.5, 0.75)); head.closeSubpath()
        path.addPath(head)
        path.addPath(head.strokedPath(StrokeStyle(lineWidth: 0.09 * u, lineJoin: .round)))
        path.addPath(Path(roundedRect: CGRect(x: pt(0.26, 0).x, y: pt(0, 0.88).y, width: 0.48 * u, height: 0.075 * u),
                          cornerRadius: 0.0375 * u))
        return path
    }
}

/// The icon's coral → pink → violet plate, for the in-app logo tile.
let brandGradient = LinearGradient(colors: [Color(red: 1.0, green: 0.45, blue: 0.33), Color(red: 0.95, green: 0.22, blue: 0.50),
                                            Color(red: 0.52, green: 0.26, blue: 0.95)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)

// MARK: - Backdrop

enum BackdropStyle: String, CaseIterable, Identifiable {
    case aurora, sunset, ocean, forest, graphite
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Eight colors around the edge of a 3×3 mesh, clockwise from top-left; the center stays neutral.
    var palette: [Color] {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch self {
        case .aurora:
            return [c(1.0, 0.30, 0.30), c(1.0, 0.55, 0.45), c(0.70, 0.35, 1.0), c(0.35, 0.45, 1.0),
                    c(0.25, 0.65, 1.0), c(0.95, 0.40, 0.60), c(0.60, 0.20, 0.85), c(0.95, 0.25, 0.50)]
        case .sunset:
            return [c(1.0, 0.45, 0.20), c(1.0, 0.70, 0.30), c(1.0, 0.40, 0.45), c(0.95, 0.30, 0.55),
                    c(0.65, 0.25, 0.75), c(1.0, 0.50, 0.35), c(0.90, 0.25, 0.30), c(1.0, 0.60, 0.25)]
        case .ocean:
            return [c(0.15, 0.55, 1.0), c(0.20, 0.80, 0.95), c(0.30, 0.90, 0.80), c(0.20, 0.60, 0.95),
                    c(0.35, 0.35, 0.95), c(0.15, 0.75, 0.90), c(0.10, 0.45, 0.85), c(0.25, 0.70, 1.0)]
        case .forest:
            return [c(0.20, 0.75, 0.45), c(0.55, 0.85, 0.35), c(0.90, 0.80, 0.30), c(0.35, 0.80, 0.60),
                    c(0.15, 0.60, 0.65), c(0.45, 0.80, 0.40), c(0.10, 0.55, 0.40), c(0.30, 0.85, 0.55)]
        case .graphite:
            return [c(0.55, 0.57, 0.62), c(0.70, 0.71, 0.75), c(0.50, 0.53, 0.62), c(0.62, 0.63, 0.70),
                    c(0.45, 0.47, 0.55), c(0.66, 0.67, 0.72), c(0.52, 0.53, 0.58), c(0.60, 0.62, 0.68)]
        }
    }
}

/// Glass needs something to refract: a slowly drifting colorful mesh behind the whole window.
/// The drift pauses while the window is in the background or Reduce Motion is on, so an idle
/// window costs nothing.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let style = settings.backdropStyle
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if #available(macOS 15.0, *) {
                let paused = !settings.animateBackdrop || reduceMotion || activeState == .inactive
                TimelineView(.animation(minimumInterval: 1.0 / 15, paused: paused)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    MeshGradient(width: 3, height: 3, points: points(t), colors: colors(style))
                        .opacity(scheme == .dark ? 0.5 : 0.4)
                }
            } else {
                RadialGradient(colors: [style.palette[0].opacity(0.25), .clear], center: .topLeading, startRadius: 0, endRadius: 650)
                RadialGradient(colors: [style.palette[4].opacity(0.2), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 700)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: style)
    }

    private func colors(_ style: BackdropStyle) -> [Color] {
        let center = scheme == .dark ? Color(white: 0.1) : Color(white: 0.97)
        let p = style.palette
        return [p[0], p[1], p[2],
                p[7], center, p[3],
                p[6], p[5], p[4]]
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        func w(_ phase: Double, _ amount: Double = 0.08) -> Float { Float(sin(t * 0.25 + phase) * amount) }
        return [
            [0, 0], [0.5 + w(0), 0], [1, 0],
            [0, 0.5 + w(1)], [0.5 + w(2, 0.12), 0.5 + w(3, 0.12)], [1, 0.5 + w(4)],
            [0, 1], [0.5 + w(5), 1], [1, 1],
        ]
    }
}
