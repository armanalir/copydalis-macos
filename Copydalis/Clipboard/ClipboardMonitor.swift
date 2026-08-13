import AppKit

@MainActor
final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let filter: ClipboardFilter
    private let writer: PasteboardWriter
    private let settings: AppSettings
    private let logger = PrivacySafeLogger(category: "clipboard")
    private let onCapture: @MainActor (ClipboardEntry) -> Void
    private var timer: Timer?
    private var workspaceObserverTokens: [NSObjectProtocol] = []
    private var sessionIsActive = true
    private var lastChangeCount: Int

    init(
        pasteboard: NSPasteboard = .general,
        filter: ClipboardFilter = ClipboardFilter(),
        writer: PasteboardWriter,
        settings: AppSettings,
        onCapture: @escaping @MainActor (ClipboardEntry) -> Void
    ) {
        self.pasteboard = pasteboard
        self.filter = filter
        self.writer = writer
        self.settings = settings
        self.onCapture = onCapture
        lastChangeCount = pasteboard.changeCount
    }

    func start(interval: TimeInterval = 0.2) {
        stop()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObserverTokens = [
            center.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.sessionIsActive = false
                }
            },
            center.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.lastChangeCount = self.pasteboard.changeCount
                    self.sessionIsActive = true
                }
            }
        ]
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        timer?.tolerance = interval * 0.2
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        workspaceObserverTokens.forEach(center.removeObserver)
        workspaceObserverTokens.removeAll()
    }

    func poll() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        guard sessionIsActive, !settings.capturePaused else { return }
        if writer.consumeInternalMutation(changeCount: currentChangeCount) {
            return
        }

        let typeNames = pasteboard.types?.map(\.rawValue) ?? []
        let containsProtectedType = filter.evaluate(typeNames: typeNames, plainText: nil) == .rejectProtectedType
        if containsProtectedType {
            logger.info("clipboard_rejected_protected_type")
            return
        }

        let decision = filter.evaluate(
            typeNames: typeNames,
            plainText: pasteboard.string(forType: .string)
        )
        guard case let .accept(text) = decision else {
            switch decision {
            case .rejectOversized:
                logger.info("clipboard_rejected_oversized")
            case .rejectEmpty, .rejectUnsupported:
                logger.info("clipboard_rejected_unsupported")
            case .rejectProtectedType:
                logger.info("clipboard_rejected_protected_type")
            case .accept:
                break
            }
            return
        }

        let source = NSWorkspace.shared.frontmostApplication
        onCapture(
            ClipboardEntry(
                text: text,
                sourceBundleIdentifier: source?.bundleIdentifier,
                sourceApplicationName: source?.localizedName
            )
        )
    }
}
