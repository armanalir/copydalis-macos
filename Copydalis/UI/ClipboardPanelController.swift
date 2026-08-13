import AppKit

// AppKit invokes local event monitors on the application's main thread. The box
// keeps NSEvent inside that callback while Swift 6 verifies the actor hop.
private final class MainThreadEventBox: @unchecked Sendable {
    let event: NSEvent

    init(_ event: NSEvent) {
        self.event = event
    }
}

@MainActor
final class ClipboardPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private final class ClipboardPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private let panel: ClipboardPanel
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var session = SelectionSession(entries: [], wraparound: false)
    private var visibleRowCount = 7
    private var showMetadata = true
    private var horizontalArrowAliases = true
    private var terminalHandler: ((SelectionSessionOutcome) -> Void)?
    private var watchdog: Timer?
    private var localEventMonitor: Any?

    override init() {
        panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 340),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()
        configurePanel()
        configureTable()
    }

    var isVisible: Bool { panel.isVisible }

    func show(
        entries: [ClipboardEntry],
        settings: AppSettings,
        terminalHandler: @escaping (SelectionSessionOutcome) -> Void
    ) {
        guard !panel.isVisible else { return }
        session = SelectionSession(entries: entries, wraparound: settings.wraparound)
        visibleRowCount = settings.popupRowCount
        showMetadata = settings.showSourceMetadata
        horizontalArrowAliases = settings.horizontalArrowAliases
        self.terminalHandler = terminalHandler
        panel.appearance = settings.appearance.appearance
        panel.alphaValue = CGFloat(settings.popupOpacity)
        tableView.reloadData()
        tableView.selectRowIndexes(entries.isEmpty ? [] : [0], byExtendingSelection: false)

        let rowCount = max(1, min(visibleRowCount, max(entries.count, 1)))
        let height = CGFloat(rowCount) * tableView.rowHeight + 20
        panel.setContentSize(NSSize(width: 560, height: min(height, 720)))
        centerOnPreferredScreen()
        installLocalEventMonitor()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(tableView)

        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.finish(self?.session.cancel() ?? .none)
            }
        }
    }

    func cancelIfVisible() {
        guard panel.isVisible else { return }
        finish(session.cancel())
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        max(session.entries.count, 1)
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let cell = NSTableCellView()
        guard session.entries.indices.contains(row) else {
            let label = NSTextField(labelWithString: "Clipboard history is empty.")
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        let entry = session.entries[row]
        let preview = NSTextField(labelWithString: Self.preview(entry.text))
        preview.lineBreakMode = .byTruncatingTail
        preview.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(preview)

        if showMetadata {
            let source = entry.sourceApplicationName ?? "Unknown application"
            let metadata = NSTextField(labelWithString: "\(source) · \(entry.capturedAt.formatted(date: .omitted, time: .shortened))")
            metadata.font = .systemFont(ofSize: 11)
            metadata.textColor = .secondaryLabelColor
            metadata.lineBreakMode = .byTruncatingTail
            metadata.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(metadata)
            NSLayoutConstraint.activate([
                preview.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                preview.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                preview.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),
                metadata.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
                metadata.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
                metadata.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 2)
            ])
        } else {
            NSLayoutConstraint.activate([
                preview.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                preview.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                preview.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        return cell
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 13
        effect.layer?.masksToBounds = true
        panel.contentView = effect
    }

    private func configureTable() {
        guard let container = panel.contentView else { return }
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ClipboardEntry"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 48
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.focusRingType = .none

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
    }

    private func installLocalEventMonitor() {
        removeLocalEventMonitor()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak self] event in
            let eventBox = MainThreadEventBox(event)
            let shouldConsume = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.panel.isVisible else { return false }
                switch eventBox.event.type {
                case .flagsChanged:
                    let activeModifiers = eventBox.event.modifierFlags.intersection([
                        .command, .shift, .control, .option
                    ])
                    if activeModifiers.isEmpty {
                        self.finish(self.session.commit())
                    }
                    return true
                case .keyDown:
                    return self.handleKeyDown(eventBox.event)
                default:
                    return false
                }
            }
            return shouldConsume ? nil : event
        }
    }

    private func removeLocalEventMonitor() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    @discardableResult
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let command = PopupInputInterpreter.command(
            forKeyCode: event.keyCode,
            horizontalArrowAliases: horizontalArrowAliases
        )
        switch command {
        case .moveOlder:
            session.move(.older)
        case .moveNewer:
            session.move(.newer)
        case .selectNewest:
            session.selectNewest()
        case .selectOldest:
            session.selectOldest()
        case .pageOlder:
            session.movePage(visibleRowCount)
        case .pageNewer:
            session.movePage(-visibleRowCount)
        case .commit:
            finish(session.commit())
            return true
        case .cancel:
            finish(session.cancel())
            return true
        case .ignore:
            return true
        case .passThrough:
            return false
        }
        updateSelection()
        return true
    }

    private func updateSelection() {
        guard session.entries.indices.contains(session.selectedIndex) else { return }
        tableView.selectRowIndexes([session.selectedIndex], byExtendingSelection: false)
        tableView.scrollRowToVisible(session.selectedIndex)
    }

    private func finish(_ outcome: SelectionSessionOutcome) {
        guard outcome != .none else { return }
        watchdog?.invalidate()
        watchdog = nil
        removeLocalEventMonitor()
        panel.orderOut(nil)
        let handler = terminalHandler
        terminalHandler = nil
        handler?(outcome)
    }

    private func centerOnPreferredScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }
        let frame = panel.frame
        panel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - frame.width / 2,
                y: visibleFrame.midY - frame.height / 2
            )
        )
    }

    private static func preview(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return String(normalized.prefix(500))
    }
}
