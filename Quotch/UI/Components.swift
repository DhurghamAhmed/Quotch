import SwiftUI

struct RingGauge: View {
    let fill: Double
    let tint: Color
    var diameter: CGFloat = 34
    var lineWidth: CGFloat = 3.5
    var value: String?
    var caption: String?

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.trackFill, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.012, min(1, fill)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Reveal.value, value: fill)

            VStack(spacing: 0) {
                if let value {
                    Text(value)
                        .font(.system(size: diameter * 0.30, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.primaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Reveal.value, value: fill)
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: diameter * 0.20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

struct RemainingBar: View {
    let fill: Double
    let tint: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Palette.trackFill)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(colors: [tint.opacity(0.75), tint],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, fill))))
                    .animation(Reveal.value, value: fill)
            }
        }
        .frame(height: height)
    }
}

struct WindowRow: View {
    let window: UsageWindow
    let metric: Metric
    let resetStyle: ResetStyle
    let provider: Provider

    private var number: String { Format.percent(Format.value(window, metric: metric)) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(window.label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let resetsAt = window.resetsAt {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(Format.resetText(for: resetsAt,
                                              now: context.date,
                                              style: resetStyle))
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.tertiaryText)
                            .monospacedDigit()
                    }
                }
            }

            Spacer(minLength: 8)

            RemainingBar(fill: Format.fill(window, metric: metric),
                         tint: window.remainingPercent < 25 ? Format.color(window) : provider.tint,
                         height: 5)
                .frame(width: 76)

            Text("\(number) \(metric.suffix)")
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 62, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(Reveal.value, value: window.usedPercent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.displayName), \(window.label)")
        .accessibilityValue("\(number) \(metric.suffix)")
    }
}

struct ProviderBadge: View {
    let provider: Provider
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
            .overlay(mark)
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var mark: some View {
        if let custom = ProviderIcons.image(for: provider) {
            Image(nsImage: custom)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size * 0.64, height: size * 0.64)
        } else {
            Image(systemName: provider.symbolName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}

@MainActor
enum ProviderIcons {

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("Quotch", isDirectory: true)
            .appendingPathComponent("Icons", isDirectory: true)
    }

    private static var cache: [Provider: NSImage?] = [:]

    static func image(for provider: Provider) -> NSImage? {
        if let cached = cache[provider] { return cached }

        let loaded = load(provider)
        cache[provider] = loaded
        return loaded
    }

    private static func load(_ provider: Provider) -> NSImage? {
        let names = ["\(provider.rawValue).png", "\(provider.rawValue).jpg",
                     "\(provider.rawValue).jpeg", "\(provider.rawValue).pdf",
                     "\(provider.rawValue).tiff"]
        for name in names {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }
}

struct AdaptiveGauge: View {
    let fill: Double
    let tint: Color
    let expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var diameter: CGFloat { expanded ? 27 : 22 }
    private var lineWidth: CGFloat { expanded ? 3.4 : 2.8 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.trackFill,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: max(0.012, min(1, fill)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : Reveal.value, value: fill)
                .shadow(color: tint.opacity(expanded ? 0.45 : 0), radius: 4)
        }
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : Reveal.chrome, value: expanded)
        .accessibilityHidden(true)
    }
}

struct CompactChip: View {
    let provider: Provider
    let state: ProviderState
    let window: UsageWindow?
    let metric: Metric
    let alignment: HorizontalAlignment
    let expanded: Bool

    var body: some View {
        HStack(spacing: 7) {
            if alignment == .trailing { Spacer(minLength: 0) }
            if let window {
                AdaptiveGauge(fill: Format.fill(window, metric: metric),
                              tint: state.status.isBlocking ? Palette.tertiaryText : provider.tint,
                              expanded: expanded)
            } else {
                StatusGlyph(status: state.status).frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(provider.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                if let window {
                    Text(Format.percent(Format.value(window, metric: metric)))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.primaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Reveal.value, value: window.usedPercent)
                } else {
                    Text("—").foregroundStyle(Palette.tertiaryText)
                }
            }
            if state.status.isBlocking, window != nil {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 8)).foregroundStyle(Palette.low)
            }
            if alignment == .leading { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 9)
        .help("\(provider.displayName) · \(window?.label ?? "Waiting for account data") · \(metric.suffix)")
    }
}

struct RailChip: View {
    let provider: Provider
    let state: ProviderState
    let window: UsageWindow?
    let metric: Metric
    let expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 5) {
            if let window {
                RingGauge(fill: Format.fill(window, metric: metric),
                          tint: state.status.isBlocking ? Palette.tertiaryText : provider.tint,
                          diameter: expanded ? 40 : 34,
                          lineWidth: expanded ? 3.6 : 3,
                          value: Format.percent(Format.value(window, metric: metric)))
                    .animation(reduceMotion ? nil : Reveal.chrome, value: expanded)
            } else {
                StatusGlyph(status: state.status).frame(width: 34, height: 34)
            }
            HStack(spacing: 3) {
                Text(provider.displayName)
                if state.status.isBlocking, window != nil {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.low)
                }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Palette.secondaryText)
        }
    }
}

struct StatusGlyph: View {
    let status: ProviderStatus

    var body: some View {
        switch status {
        case .loading, .idle:
            Text("—")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.tertiaryText)
        case .needsLogin:
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 10))
                .foregroundStyle(Palette.low)
        case .throttled:
            Image(systemName: "hourglass")
                .font(.system(size: 10))
                .foregroundStyle(Palette.fair)
        case .error, .ok:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(Palette.spent)
        }
    }
}

struct NotchShape: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.height, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct FlushShape: InsettableShape {
    var corners: CornerRounding
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> FlushShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard box.width > 0, box.height > 0 else { return Path() }

        let limit = min(box.width, box.height) / 2
        let radius = max(0, min(cornerRadius, limit))

        let topLeft = corners.topLeft ? radius : 0
        let topRight = corners.topRight ? radius : 0
        let bottomRight = corners.bottomRight ? radius : 0
        let bottomLeft = corners.bottomLeft ? radius : 0

        var path = Path()
        path.move(to: CGPoint(x: box.minX + topLeft, y: box.minY))

        path.addLine(to: CGPoint(x: box.maxX - topRight, y: box.minY))
        if topRight > 0 {
            path.addArc(center: CGPoint(x: box.maxX - topRight, y: box.minY + topRight),
                        radius: topRight,
                        startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        }

        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - bottomRight))
        if bottomRight > 0 {
            path.addArc(center: CGPoint(x: box.maxX - bottomRight, y: box.maxY - bottomRight),
                        radius: bottomRight,
                        startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }

        path.addLine(to: CGPoint(x: box.minX + bottomLeft, y: box.maxY))
        if bottomLeft > 0 {
            path.addArc(center: CGPoint(x: box.minX + bottomLeft, y: box.maxY - bottomLeft),
                        radius: bottomLeft,
                        startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }

        path.addLine(to: CGPoint(x: box.minX, y: box.minY + topLeft))
        if topLeft > 0 {
            path.addArc(center: CGPoint(x: box.minX + topLeft, y: box.minY + topLeft),
                        radius: topLeft,
                        startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }

        path.closeSubpath()
        return path
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 22, height: 22)
            .background(
                Circle().fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.06))
            )
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct TextLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Palette.primaryText : Palette.tertiaryText)
            .contentShape(Rectangle())
    }
}

struct GlassSurface: View {
    var cornerRadius: CGFloat = 22
    var corners: CornerRounding = .all
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = FlushShape(corners: corners, cornerRadius: cornerRadius)
        ZStack {
            if reduceTransparency {
                Color(red: 0.08, green: 0.09, blue: 0.12)
            } else {
                VisualEffectBackground(material: .hudWindow)
                Color(red: 0.035, green: 0.045, blue: 0.075).opacity(0.28)
                LinearGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(
            LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06), .white.opacity(0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75))
    }
}
