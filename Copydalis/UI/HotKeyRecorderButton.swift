import AppKit

private final class RecorderEventBox: @unchecked Sendable {
    let event: NSEvent

    init(_ event: NSEvent) {
        self.event = event
    }
}

@MainActor
final class HotKeyRecorderButton: NSButton {
    var onRecorded: ((HotKeyConfiguration) -> Void)?
    var onRecordingStateChanged: ((Bool) -> Void)?
    private var configuration: HotKeyConfiguration = .defaultShortcut
    private var isRecordingShortcut = false
    private var localEventMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    func setConfiguration(_ configuration: HotKeyConfiguration) {
        self.configuration = configuration
        if !isRecordingShortcut {
            title = configuration.displayName
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        if !handleKeyDown(event) {
            super.keyDown(with: event)
        }
    }

    override func resignFirstResponder() -> Bool {
        if isRecordingShortcut {
            stopRecording(configuration: configuration, notify: false, clearFirstResponder: false)
        }
        return super.resignFirstResponder()
    }

    func cancelRecording() {
        guard isRecordingShortcut else { return }
        stopRecording(configuration: configuration, notify: false, clearFirstResponder: true)
    }

    private func beginRecording() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        title = "Type shortcut…"
        onRecordingStateChanged?(true)
        installLocalEventMonitor()
        window?.makeFirstResponder(self)
    }

    @discardableResult
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isRecordingShortcut else { return false }
        if event.keyCode == 53 {
            cancelRecording()
            return true
        }
        guard let recorded = HotKeyConfiguration.from(event: event) else {
            NSSound.beep()
            return true
        }
        stopRecording(configuration: recorded, notify: true, clearFirstResponder: true)
        return true
    }

    private func installLocalEventMonitor() {
        removeLocalEventMonitor()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let eventBox = RecorderEventBox(event)
            let consumed = MainActor.assumeIsolated {
                self?.handleKeyDown(eventBox.event) ?? false
            }
            return consumed ? nil : event
        }
    }

    private func removeLocalEventMonitor() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func stopRecording(
        configuration: HotKeyConfiguration,
        notify: Bool,
        clearFirstResponder: Bool
    ) {
        guard isRecordingShortcut else { return }
        self.configuration = configuration
        isRecordingShortcut = false
        removeLocalEventMonitor()
        title = configuration.displayName
        if notify {
            onRecorded?(configuration)
        }
        onRecordingStateChanged?(false)
        if clearFirstResponder {
            window?.makeFirstResponder(nil)
        }
    }
}
