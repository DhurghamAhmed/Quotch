import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: UsageStore

    @State private var claudeInterval: Double = Limits.claudeDefaultInterval
    @State private var codexInterval: Double = Limits.codexDefaultInterval

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    displaySection
                    Divider()
                    windowsSection
                    Divider()
                    providersSection
                    Divider()
                    privacyNote
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 470)
        .onAppear {
            claudeInterval = store.settings.claudeInterval
            codexInterval = store.settings.codexInterval
        }
    }

    private func setting<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in
                var updated = store.settings
                updated[keyPath: keyPath] = newValue
                store.applySettings(updated)
            }
        )
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Display")

            Picker("Show", selection: setting(\.metric)) {
                ForEach(Metric.allCases) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .pickerStyle(.segmented)

            Text(store.settings.metric == .used
                 ? "\"13%\" with the bar 13% across — both climb toward the limit, the way Claude "
                   + "Code's /usage panel reads."
                 : "\"74% left\" with the bar 74% across — both run down to zero as quota is spent.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Reset time", selection: setting(\.resetStyle)) {
                ForEach(ResetStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Text(store.settings.resetStyle == .relative
                 ? "\"Resets in 3h\"."
                 : "\"Resets 8:50 AM\", with the date added when it isn't today.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label("Circular at rest · Straight bars on hover", systemImage: "cursorarrow.rays")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("Colour always tracks how much is left, whichever number you display — a bar at "
                 + "92% used and one at 8% left mean the same thing and must look the same.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var windowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Quotas to show")

            let discovered = store.discoveredWindows
            if discovered.isEmpty {
                Text("Connect an account to choose which quotas appear.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(discovered) { entry in
                    Toggle(isOn: windowBinding(provider: entry.provider, key: entry.window.key)) {
                        HStack(spacing: 6) {
                            Text(entry.provider.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(entry.window.label)
                                .font(.system(size: 11))
                            Spacer()
                            Text(Format.percent(Format.value(entry.window,
                                                             metric: store.settings.metric)))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text("Session quota is the short usage allowance. Weekly quota covers the week; model names identify separate model allowances. The compact number shows the selected quota closest to its limit.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func windowBinding(provider: Provider, key: String) -> Binding<Bool> {
        Binding(
            get: { store.settings.isWindowVisible(provider: provider, key: key) },
            set: { visible in
                var updated = store.settings
                updated.setWindow(provider: provider, key: key, visible: visible)
                store.applySettings(updated)
            }
        )
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Providers")

            providerBlock(
                title: "Claude",
                enabled: setting(\.claudeEnabled),
                interval: $claudeInterval,
                range: Limits.claudeMinInterval...900,
                commit: { value in
                    var updated = store.settings
                    updated.claudeInterval = max(Limits.claudeMinInterval, value)
                    store.applySettings(updated)
                },
                note: "Activity requests an account sync. Claude does not include subscription percentages in local activity, so updates depend on the server and its rate limits."
            )

            providerBlock(
                title: "Codex",
                enabled: setting(\.codexEnabled),
                interval: $codexInterval,
                range: Limits.codexMinInterval...900,
                commit: { value in
                    var updated = store.settings
                    updated.codexInterval = max(Limits.codexMinInterval, value)
                    store.applySettings(updated)
                },
                note: "Quota events update the panel as Codex writes them. Background sync also checks usage from other devices."
            )
        }
    }

    @ViewBuilder
    private func providerBlock(title: String,
                               enabled: Binding<Bool>,
                               interval: Binding<Double>,
                               range: ClosedRange<Double>,
                               commit: @escaping (Double) -> Void,
                               note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: enabled)
                .font(.system(size: 12, weight: .semibold))
            HStack {
                Text("Background sync")
                    .font(.system(size: 11))
                Slider(value: interval, in: range, step: 30) { editing in
                    if !editing { commit(interval.wrappedValue) }
                }
                Text(intervalLabel(interval.wrappedValue))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 58, alignment: .trailing)
            }
            .disabled(!enabled.wrappedValue)
            Text(note)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func intervalLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainder = total % 60
        if minutes == 0 { return "\(remainder)s" }
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
    }

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Credentials are read locally and sent only to the service that issued them.")
            Text("Local activity is watched for quota updates. Conversation text is never retained or sent.")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
}
