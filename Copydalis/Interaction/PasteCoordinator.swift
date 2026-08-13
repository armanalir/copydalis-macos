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
    private static let activationPollInterval = 0.05
    private static let maximumActivationAttempts = 10

    private let writer: PasteboardWriter
    private let logger = PrivacySafeLogger(category: "paste")

    init(writer: PasteboardWriter) {
        self.writer = writer
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
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

        NSApp.yieldActivation(to: targetApplication)
        _ = targetApplication.activate(from: .current, options: [])
        verifyTargetAndPaste(
            targetApplication: targetApplication,
            attempt: 1,
            completion: completion
        )
        return .pasteScheduled
    }

    private func verifyTargetAndPaste(
        targetApplication: NSRunningApplication,
        attempt: Int,
        completion: ((PasteResult) -> Void)?
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationPollInterval) { [weak self, targetApplication] in
            guard let self, !targetApplication.isTerminated else {
                completion?(.copiedOnlyTargetUnavailable)
                return
            }

            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if PasteTargetPolicy.mayPostEvent(
                expectedProcessIdentifier: targetApplication.processIdentifier,
                frontmostProcessIdentifier: frontmostPID,
                targetIsTerminated: targetApplication.isTerminated
            ) {
                completion?(self.postCommandV(to: targetApplication.processIdentifier))
                return
            }

            guard PasteTargetPolicy.shouldRetryActivation(
                attempt: attempt,
                maximumAttempts: Self.maximumActivationAttempts
            ) else {
                self.logger.info("automatic_paste_target_mismatch")
                completion?(.copiedOnlyTargetMismatch)
                return
            }

            self.verifyTargetAndPaste(
                targetApplication: targetApplication,
                attempt: attempt + 1,
                completion: completion
            )
        }
    }

    private func postCommandV(to processIdentifier: pid_t) -> PasteResult {
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
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        logger.info("automatic_paste_posted")
        return .pasted
    }

    func requestAccessibilityPermission() {
        // Swift 6 imports kAXTrustedCheckOptionPrompt as concurrency-unsafe
        // mutable C state. This is its documented, stable dictionary key.
        let options = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
