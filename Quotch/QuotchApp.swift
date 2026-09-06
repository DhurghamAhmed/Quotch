import SwiftUI
import AppKit

@main
struct QuotchApp: App {
    @NSApplicationDelegateAdaptor(AppCoordinator.self) private var coordinator

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {

    static private(set) var shared: AppCoordinator?

    let store = UsageStore()
    private(set) var notch: NotchController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCoordinator.shared = self

        NSApp.setActivationPolicy(.accessory)

        let controller = NotchController(store: store)
        controller.start()
        notch = controller

        buildStatusItem()
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        notch?.stop()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                                   accessibilityDescription: "Usage")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        menu.addItem(action(title: "Refresh Now", selector: #selector(refreshNow), key: "r"))
        menu.addItem(action(title: "Toggle Panel", selector: #selector(togglePanel), key: ""))

        menu.addItem(.separator())

        let positionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        positionItem.submenu = buildPositionMenu()
        menu.addItem(positionItem)

        menu.addItem(.separator())

        menu.addItem(action(title: "Settings…", selector: #selector(openSettings), key: ","))

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit Quotch",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    private func buildPositionMenu() -> NSMenu {
        let submenu = NSMenu()
        let entries: [(String, Placement)] = [
            ("Notch", .docked),
            ("Top Left", .topLeft),
            ("Top Centre", .topCenter),
            ("Top Right", .topRight),
            ("Left", .leftMiddle),
            ("Right", .rightMiddle),
            ("Bottom Left", .bottomLeft),
            ("Bottom Right", .bottomRight)
        ]

        for (index, entry) in entries.enumerated() {
            let item = NSMenuItem(title: entry.0,
                                  action: #selector(choosePosition(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = index
            submenu.addItem(item)
        }
        return submenu
    }

    private func action(title: String, selector: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func refreshNow() {
        store.refreshAll(manual: true)
    }

    @objc private func togglePanel() {
        notch?.toggle()
    }

    @objc private func choosePosition(_ sender: NSMenuItem) {
        let placements: [Placement] = [
            .docked, .topLeft, .topCenter, .topRight,
            .leftMiddle, .rightMiddle, .bottomLeft, .bottomRight
        ]
        guard placements.indices.contains(sender.tag) else { return }
        notch?.apply(placement: placements[sender.tag], animated: true)
    }

    @objc private func openSettings() {
        showSettings()
    }

    func showSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(store: store))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Quotch Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
