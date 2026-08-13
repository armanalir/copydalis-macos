import AppKit

@main
@MainActor
final class CopydalisApp: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let pasteboardWriter = PasteboardWriter()
    private lazy var pasteCoordinator = PasteCoordinator(writer: pasteboardWriter)
    private let panelController = ClipboardPanelController()
    private let hotKeyRegistrar = CarbonHotKeyRegistrar()

    private var repository: SQLiteHistoryRepository?
    private var clipboardMonitor: ClipboardMonitor?
    private var statusController: StatusItemController?
    private var settingsController: SettingsWindowController?
    private var cachedEntries: [ClipboardEntry] = []
    private var targetApplication: NSRunningApplication?
    private var registeredHotKey = HotKeyConfiguration.defaultShortcut
    private let logger = PrivacySafeLogger(category: "application")

    private var interactionTestMode: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--interaction-test-mode")
#else
        false
#endif
    }

    static func main() {
        let application = NSApplication.shared
        let delegate = CopydalisApp()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            configureStatusItem()
            configureSettingsWindow()
            try configureHotKey()

            if interactionTestMode {
                cachedEntries = Self.syntheticEntries
                statusController?.update(entries: cachedEntries)
                logger.info("interaction_test_mode_started")
                return
            }

            let repository = try makeRepository()
            self.repository = repository
            configureClipboardMonitor(repository: repository)
            refreshCache()
            logger.info("application_started")
        } catch {
            logger.error("application_start_failed")
            presentFatalStartupAlert()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
        panelController.cancelIfVisible()
        hotKeyRegistrar.unregister()
    }

    private func makeRepository() throws -> SQLiteHistoryRepository {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("Copydalis", isDirectory: true)
        let database = directory.appendingPathComponent("History.sqlite3", isDirectory: false)
        return try SQLiteHistoryRepository(
            databaseURL: database,
            keyStore: KeychainKeyMaterialStore()
        )
    }

    private func configureStatusItem() {
        let controller = StatusItemController(settings: settings)
        controller.onMenuOpening = { [weak self] in
            self?.frontmostExternalApplication()
        }
        controller.onSelectEntry = { [weak self] entry, target in
            guard let self else { return }
            let shouldPaste = self.settings.menuSelectionAction == .paste
            _ = self.pasteCoordinator.commit(
                entry: entry,
                targetApplication: target,
                pasteAutomatically: shouldPaste
            )
            self.moveToNewestIfNeeded(entry)
        }
        controller.onToggleCapture = { [weak self] in
            guard let self else { return }
            self.settings.capturePaused.toggle()
            self.statusController?.updatePausedAppearance()
        }
        controller.onClearHistory = { [weak self] in self?.confirmAndClearHistory() }
        controller.onOpenSettings = { [weak self] in self?.settingsController?.show() }
        statusController = controller
    }

    private func configureSettingsWindow() {
        settingsController = SettingsWindowController(
            settings: settings,
            pasteCoordinator: pasteCoordinator,
            onSettingsChanged: { [weak self] in
                self?.applySettingsChanges()
            }
        )
    }

    private func configureClipboardMonitor(repository: SQLiteHistoryRepository) {
        let monitor = ClipboardMonitor(
            writer: pasteboardWriter,
            settings: settings,
            onCapture: { [weak self] entry in
                guard let self else { return }
                Task {
                    do {
                        try await repository.insert(
                            entry,
                            capacity: self.settings.historyCapacity,
                            removeExactDuplicates: self.settings.removeExactDuplicates
                        )
                        await self.loadCache(from: repository)
                    } catch {
                        self.logger.error("clipboard_persistence_failed")
                    }
                }
            }
        )
        clipboardMonitor = monitor
        monitor.start()
    }

    private func configureHotKey() throws {
        let configuration = settings.hotKey
        try hotKeyRegistrar.register(configuration: configuration) { [weak self] in
            self?.beginSelectionSession()
        }
        registeredHotKey = configuration
    }

    private func applySettingsChanges() {
        refreshCache()
        let requested = settings.hotKey
        guard requested != registeredHotKey else { return }
        do {
            try configureHotKey()
        } catch {
            settings.hotKey = registeredHotKey
            try? hotKeyRegistrar.register(configuration: registeredHotKey) { [weak self] in
                self?.beginSelectionSession()
            }
            presentOperationError("That global shortcut is unavailable. The previous shortcut was restored.")
        }
    }

    private func beginSelectionSession() {
        guard !panelController.isVisible else { return }
        targetApplication = frontmostExternalApplication()
        panelController.show(entries: cachedEntries, settings: settings) { [weak self] outcome in
            guard let self else { return }
            defer { self.targetApplication = nil }
            guard case let .commit(entry) = outcome else { return }
            _ = self.pasteCoordinator.commit(
                entry: entry,
                targetApplication: self.targetApplication,
                pasteAutomatically: true
            )
            self.moveToNewestIfNeeded(entry)
        }
    }

    private func refreshCache() {
        guard let repository else { return }
        Task {
            do {
                try await repository.trim(to: settings.historyCapacity)
            } catch {
                logger.error("history_trim_failed")
            }
            await loadCache(from: repository)
        }
    }

    private func moveToNewestIfNeeded(_ entry: ClipboardEntry) {
        guard settings.movePastedToNewest, let repository else { return }
        Task {
            do {
                try await repository.moveToNewest(id: entry.id)
                await loadCache(from: repository)
            } catch {
                logger.error("history_reorder_failed")
            }
        }
    }

    private func loadCache(from repository: SQLiteHistoryRepository) async {
        do {
            let entries = try await repository.fetchNewest(limit: settings.historyCapacity)
            cachedEntries = entries
            statusController?.update(entries: entries)
        } catch {
            logger.error("history_fetch_failed")
        }
    }

    private func confirmAndClearHistory() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "This removes all Copydalis entries and rotates the encryption key. It does not clear the current macOS clipboard or external backups."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn, let repository else { return }

        Task {
            do {
                try await repository.clearAndRotateKey()
                cachedEntries = []
                statusController?.update(entries: [])
            } catch {
                logger.error("history_clear_failed")
                presentOperationError("The history could not be cleared safely.")
            }
        }
    }

    private func frontmostExternalApplication() -> NSRunningApplication? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        return frontmost?.processIdentifier == currentPID ? targetApplication : frontmost
    }

    private func presentFatalStartupAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Copydalis could not start securely."
        alert.informativeText = "The encrypted history store or its Keychain key could not be opened. No clipboard monitoring has started."
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func presentOperationError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static let syntheticEntries = [
        ClipboardEntry(
            text: "Copydalis synthetic newest item",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_003),
            sourceBundleIdentifier: "com.copydalis.synthetic",
            sourceApplicationName: "Synthetic Source"
        ),
        ClipboardEntry(
            text: "Copydalis synthetic second item",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_002),
            sourceBundleIdentifier: "com.copydalis.synthetic",
            sourceApplicationName: "Synthetic Source"
        ),
        ClipboardEntry(
            text: "Copydalis synthetic oldest item",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_001),
            sourceBundleIdentifier: "com.copydalis.synthetic",
            sourceApplicationName: "Synthetic Source"
        )
    ]
}
