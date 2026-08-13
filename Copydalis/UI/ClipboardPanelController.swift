import AppKit

@MainActor
final class ClipboardPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private final class ClipboardPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private final class EventCapturingView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?
        var onFlagsChanged: ((NSEvent.ModifierFlags) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            onKeyDown?(event)
        }

        override func flagsChanged(with event: NSEvent) {
            onFlagsChanged?(event.modifierFlags)
        }
    }

    private let panel: ClipboardPanel
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let eventView = EventCapturingView()
    private var session = SelectionSession(entries: [], wraparound: false)
    private var visibleRowCount = 7
    private var showMetadata = true
    private var horizontalArrowAliases = true
    private var terminalHandler: ((SelectionSessionOutcome) -> Void)?
    private var watchdog: Timer?

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
        configureEvents()
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
        tableView.reloadData()
        tableView.selectRowIndexes(entries.isEmpty ? [] : [0], byExtendingSelection: false)

        let rowCount = max(1, min(visibleRowCount, max(entries.count, 1)))
        let height = CGFloat(rowCount) * tableView.rowHeight + 20
        panel.setContentSize(NSSize(width: 560, height: min(height, 720)))
        centerOnPreferredScreen()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(eventView)

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

        eventView.translatesAutoresizingMaskIntoConstraints = false
        eventView.alphaValue = 0
        container.addSubview(eventView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            eventView.widthAnchor.constraint(equalToConstant: 1),
            eventView.heightAnchor.constraint(equalToConstant: 1),
            eventView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            eventView.topAnchor.constraint(equalTo: container.topAnchor)
        ])
    }

    private func configureEvents() {
        eventView.onFlagsChanged = { [weak self] flags in
            guard let self else { return }
            let activeModifiers = flags.intersection([.command, .shift, .control, .option])
            if activeModifiers.isEmpty {
                self.finish(self.session.commit())
            }
        }
        eventView.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event)
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case 125:
            session.move(.older)
        case 126:
            session.move(.newer)
        case 124 where horizontalArrowAliases:
            session.move(.older)
        case 123 where horizontalArrowAliases:
            session.move(.newer)
        case 115:
            session.selectNewest()
        case 119:
            session.selectOldest()
        case 121:
            session.movePage(visibleRowCount)
        case 116:
            session.movePage(-visibleRowCount)
        case 36, 76:
            finish(session.commit())
            return
        case 53:
            finish(session.cancel())
            return
        case 9:
            return
        default:
            return
        }
        updateSelection()
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
