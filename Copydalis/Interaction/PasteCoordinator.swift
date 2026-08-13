import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum PasteResult: Equatable, Sendable {
    case pasteScheduled
    case pasted
    case copiedOnlyAccessibilityDenied
    case copiedOnlyByPreference
    case copiedOnlyTargetUnavailable
    case copiedOnlyTargetMismatch
    case copiedOnlyEventCreationFailed
}

@MainActor
final class PasteCoordinator {
    private let writer: PasteboardWriter
    private let logger = PrivacySafeLogger(category: "paste")

    init(writer: PasteboardWriter) {
        self.writer = writer
    }

    func commit(
        entry: ClipboardEntry,
        targetApplication: NSRunningApplication?,
        pasteAutomatically: Bool,
        completion: ((PasteResult) -> Void)? = nil
    ) -> PasteResult {
        writer.write(entry.text)
        guard pasteAutomatically else {
            return .copiedOnlyByPreference
        }
        guard AXIsProcessTrusted() else {
            logger.info("automatic_paste_accessibility_denied")
            return .copiedOnlyAccessibilityDenied
        }

        guard let targetApplication else {
            logger.info("automatic_paste_target_unavailable")
            return .copiedOnlyTargetUnavailable
        }

        targetApplication.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak targetApplication] in
            guard let self, let targetApplication else {
                completion?(.copiedOnlyTargetUnavailable)
                return
            }
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard PasteTargetPolicy.mayPostEvent(
                expectedProcessIdentifier: targetApplication.processIdentifier,
                frontmostProcessIdentifier: frontmostPID,
                targetIsTerminated: targetApplication.isTerminated
            ) else {
                self.logger.info("automatic_paste_target_mismatch")
                completion?(.copiedOnlyTargetMismatch)
                return
            }
            completion?(self.postCommandV())
        }
        return .pasteScheduled
    }

    private func postCommandV() -> PasteResult {
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            logger.error("automatic_paste_event_creation_failed")
            return .copiedOnlyEventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        logger.info("automatic_paste_posted")
        return .pasted
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
