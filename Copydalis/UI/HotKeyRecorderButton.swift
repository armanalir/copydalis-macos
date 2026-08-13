import AppKit

@MainActor
final class HotKeyRecorderButton: NSButton {
    var onRecorded: ((HotKeyConfiguration) -> Void)?
    private var configuration: HotKeyConfiguration = .defaultShortcut
    private var isRecordingShortcut = false

    override var acceptsFirstResponder: Bool { true }

    func setConfiguration(_ configuration: HotKeyConfiguration) {
        self.configuration = configuration
        if !isRecordingShortcut {
            title = configuration.displayName
        }
    }

    override func mouseDown(with event: NSEvent) {
        isRecordingShortcut = true
        title = "Type shortcut…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            finishRecording(configuration)
            return
        }
        guard let recorded = HotKeyConfiguration.from(event: event) else {
            NSSound.beep()
            return
        }
        finishRecording(recorded)
        onRecorded?(recorded)
    }

    override func resignFirstResponder() -> Bool {
        isRecordingShortcut = false
        title = configuration.displayName
        return super.resignFirstResponder()
    }

    private func finishRecording(_ configuration: HotKeyConfiguration) {
        self.configuration = configuration
        isRecordingShortcut = false
        title = configuration.displayName
        window?.makeFirstResponder(nil)
    }
}
