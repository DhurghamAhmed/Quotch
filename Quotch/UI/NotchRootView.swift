import SwiftUI
import AppKit

extension Provider {
    var tint: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.55, blue: 0.36)
        case .codex:  return Color(red: 0.45, green: 0.72, blue: 0.95)
        }
    }

    var symbolName: String {
        switch self {
        case .claude: return "sun.max.fill"
        case .codex:  return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct NotchRootView: View {
    @ObservedObject var controller: NotchController
    @ObservedObject var store: UsageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var frames: PanelFrames { controller.frames }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private var cardAnchor: UnitPoint {
        switch frames.direction {
        case .down:  return .top
        case .up:    return .bottom
        case .left:  return .trailing
        case .right: return .leading
        }
    }

    private var cardTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let vertical = frames.direction == .down || frames.direction == .up
        return .asymmetric(
            insertion: .modifier(
                active: Unfold(progress: 0, anchor: cardAnchor, vertical: vertical),
                identity: Unfold(progress: 1, anchor: cardAnchor, vertical: vertical)
            ),
            removal: .scale(scale: 0.97, anchor: cardAnchor).combined(with: .opacity)
        )
    }

    private var alignment: Alignment {
        switch frames.direction {
        case .down:  return .top
        case .up:    return .bottom
        case .left:  return .trailing
        case .right: return .leading
        }
    }

    @ViewBuilder
    private var content: some View {
        switch frames.direction {
        case .down:  VStack(spacing: 0) { chrome; if controller.isExpanded { revealedCard } }
        case .up:    VStack(spacing: 0) { if controller.isExpanded { revealedCard }; chrome }
        case .left:  HStack(spacing: 0) { if controller.isExpanded { revealedCard }; chrome }
        case .right: HStack(spacing: 0) { chrome; if controller.isExpanded { revealedCard } }
        }
    }

    @ViewBuilder
    private var chrome: some View {
        if frames.isRail {
            RailStrip(store: store, frames: frames, expanded: controller.isExpanded)
                .frame(width: frames.railWidth)
        } else {
            CollapsedStrip(store: store, frames: frames, isDragging: controller.isDragging, expanded: controller.isExpanded)
                .frame(height: frames.stripHeight)
        }
    }

    private var revealedCard: some View {
        ExpandedCard(store: store, controller: controller)
            .transition(cardTransition)
    }
}

private struct Unfold: ViewModifier {
    let progress: Double
    let anchor: UnitPoint
    let vertical: Bool

    func body(content: Content) -> some View {
        let major = 0.86 + 0.14 * progress
        let minor = 0.975 + 0.025 * progress
        return content
            .scaleEffect(x: vertical ? minor : major,
                         y: vertical ? major : minor,
                         anchor: anchor)
            .opacity(min(1, progress * 1.35))
    }
}

struct CollapsedStrip: View {
    @ObservedObject var store: UsageStore
    let frames: PanelFrames
    let isDragging: Bool
    let expanded: Bool

    private var providers: [Provider] { store.activeProviders }

    var body: some View {
        Group {
            if frames.isNotchDocked {
                docked
            } else {
                pill
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var docked: some View {
        ZStack {
            GlassSurface(cornerRadius: 0)
                .clipShape(NotchShape(cornerRadius: NotchMetrics.notchCornerRadius))
            Color.black.frame(width: frames.notchWidth)
            HStack(spacing: 0) {
                chip(index: 0, alignment: .leading)
                    .frame(width: NotchMetrics.wingWidth)
                Spacer(minLength: 0)
                    .frame(width: frames.notchWidth)
                chip(index: 1, alignment: .trailing)
                    .frame(width: NotchMetrics.wingWidth)
            }
        }
    }

    private var pill: some View {
        HStack(spacing: 0) {
            chip(index: 0, alignment: .center)
            if providers.count > 1 {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(width: 1, height: 12)
            }
            chip(index: 1, alignment: .center)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlassSurface(cornerRadius: 24, corners: frames.corners))
        .shadow(color: .black.opacity(isDragging ? 0.5 : 0.3),
                radius: isDragging ? 16 : 8, y: isDragging ? 8 : 3)
        .animation(Reveal.chrome, value: isDragging)
    }

    @ViewBuilder
    private func chip(index: Int, alignment: HorizontalAlignment) -> some View {
        if index < providers.count {
            let provider = providers[index]
            CompactChip(provider: provider,
                        state: store.state(provider),
                        window: store.headline(for: provider),
                        metric: store.settings.metric,
                        alignment: alignment, expanded: expanded)
        } else {
            Color.clear
        }
    }
}

struct RailStrip: View {
    @ObservedObject var store: UsageStore
    let frames: PanelFrames
    let expanded: Bool

    var body: some View {
        VStack(spacing: 10) {
            ForEach(store.activeProviders) { provider in
                RailChip(provider: provider,
                         state: store.state(provider),
                         window: store.headline(for: provider),
                         metric: store.settings.metric,
                          expanded: expanded)
            }
        }
        .padding(.vertical, NotchMetrics.railPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlassSurface(cornerRadius: NotchMetrics.railCornerRadius,
                                 corners: frames.corners))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

struct ExpandedCard: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var controller: NotchController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(store.activeProviders.enumerated()), id: \.element) { index, provider in
                        ProviderSection(provider: provider,
                                        state: store.state(provider),
                                        windows: store.windows(for: provider),
                                        headline: store.headline(for: provider),
                                        settings: store.settings,
                                        revealIndex: index)
                    }

                    if store.activeProviders.isEmpty {
                        Text("Both providers are switched off in Settings.")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .padding(.horizontal, 18)
        .padding(.top, 17)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlassSurface(cornerRadius: NotchMetrics.cardCornerRadius))
        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
        .padding(4)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)

            Text("Usage overview")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.primaryText)

            Spacer()

            Text(store.settings.metric == .used ? "CONSUMED" : "AVAILABLE")
                .font(.system(size: 8, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Palette.tertiaryText)

            Button {
                store.refreshAll(manual: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
            }
            .buttonStyle(IconButtonStyle())
            .disabled(store.activeProviders.allSatisfy { store.state($0).isRefreshing })
            .help("Sync account usage")
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Settings") { AppCoordinator.shared?.showSettings() }
                .buttonStyle(TextLinkStyle())
            Button("Reset position") { controller.resetPlacement() }
                .buttonStyle(TextLinkStyle())
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(TextLinkStyle())
        }
        .padding(.top, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
                .offset(y: -6)
        }
    }
}

struct ProviderSection: View {
    let provider: Provider
    let state: ProviderState
    let windows: [UsageWindow]
    let headline: UsageWindow?
    let settings: AppSettings
    let revealIndex: Int

    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow

            if !windows.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(windows) { window in
                        WindowRow(window: window,
                                  metric: settings.metric,
                                  resetStyle: settings.resetStyle,
                                  provider: provider)
                    }
                }
                .padding(.top, 8)
            } else if state.snapshot != nil {
                Text("No quotas selected. Choose them in Settings.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryText)
            }

            if state.snapshot?.limitReached == true {
                Label("Limit reached", systemImage: "exclamationmark.octagon.fill")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Palette.spent)
            }

            statusLine
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LinearGradient(colors: [provider.tint.opacity(0.09), Color.white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 6)
        .blur(radius: revealed ? 0 : 3.5)
        .animation(Reveal.row(index: revealIndex), value: revealed)
        .onAppear { revealed = true }
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            ProviderBadge(provider: provider, tint: provider.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text(connectionLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.tertiaryText)
            }

            Spacer()

            if state.isRefreshing && headline == nil {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.62)
            } else if let headline {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Format.percent(Format.value(headline, metric: settings.metric)))
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(Format.color(headline))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Reveal.value, value: headline.usedPercent)
                    Text(settings.metric.suffix)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
        }
    }

    private var connectionLabel: String {
        if state.isRefreshing { return "Syncing account…" }
        if state.status.isBlocking { return state.snapshot == nil ? "Connection needed" : "Last confirmed values" }
        return state.snapshot?.source.rawValue ?? "Connecting…"
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state.status {
        case .needsLogin(let message):
            note(message, color: Palette.low, icon: "person.crop.circle.badge.exclamationmark")
        case .throttled:
            note("Sync paused by provider · Last confirmed values",
                 color: Palette.fair, icon: "hourglass")
        case .error(let message):
            note(message, color: Palette.spent, icon: "exclamationmark.triangle.fill")
        case .loading where state.snapshot == nil:
            note("Loading…", color: Palette.tertiaryText, icon: "ellipsis")
        case .idle, .ok, .loading:
            EmptyView()
        }
    }

    private func note(_ message: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8.5))
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 9.5))
        .foregroundStyle(color)
    }
}
