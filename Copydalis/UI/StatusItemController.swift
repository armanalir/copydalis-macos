import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let settings: AppSettings
    private var entries: [ClipboardEntry] = []
    private var menuTargetApplication: NSRunningApplication?

    var onSelectEntry: ((ClipboardEntry, NSRunningApplication?) -> Void)?
    var onToggleCapture: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onMenuOpening: (() -> NSRunningApplication?)?

    init(settings: AppSettings) {
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Copydalis")
        statusItem.button?.toolTip = "Copydalis"
        statusItem.menu = menu
        menu.delegate = self
        rebuildMenu()
    }

    func update(entries: [ClipboardEntry]) {
        self.entries = entries
        rebuildMenu()
    }

    func updatePausedAppearance() {
        let symbol = settings.capturePaused ? "clipboard.fill" : "doc.on.clipboard"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Copydalis")
        statusItem.button?.appearsDisabled = settings.capturePaused
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuTargetApplication = onMenuOpening?()
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let visibleEntries = entries.prefix(settings.menuItemCount)
        if visibleEntries.isEmpty {
            let empty = NSMenuItem(title: "Clipboard history is empty", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (index, entry) in visibleEntries.enumerated() {
                let item = NSMenuItem(
                    title: Self.menuPreview(entry.text),
                    action: #selector(selectEntry(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                item.toolTip = entry.sourceApplicationName
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let pauseTitle = settings.capturePaused ? "Resume Clipboard Capture" : "Pause Clipboard Capture"
        let pause = NSMenuItem(title: pauseTitle, action: #selector(toggleCapture), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let about = NSMenuItem(title: "About Copydalis", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Copydalis", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func selectEntry(_ sender: NSMenuItem) {
        guard entries.indices.contains(sender.tag) else { return }
        onSelectEntry?(entries[sender.tag], menuTargetApplication)
    }

    @objc private func toggleCapture() { onToggleCapture?() }
    @objc private func clearHistory() { onClearHistory?() }
    @objc private func openSettings() { onOpenSettings?() }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private static func menuPreview(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let value = String(normalized.prefix(100))
        return value.isEmpty ? "(Empty)" : value
    }
}
