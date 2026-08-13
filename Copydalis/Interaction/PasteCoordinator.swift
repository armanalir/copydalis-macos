import AppKit
import ApplicationServices

enum PasteResult: Equatable, Sendable {
    case pasteScheduled
    case pasted
    case copiedOnlyAccessibilityDenied
    case copiedOnlyByPreference
    case copiedOnlyTargetUnavailable
    case copiedOnlyTargetMismatch
    case copiedOnlyPasteCommandUnavailable(PasteCommandDiagnostic)
    case copiedOnlyPasteCommandFailed(PasteCommandDiagnostic)
}

struct PasteCommandDiagnostic: Equatable, Sendable {
    let stage: String
    let accessibilityErrorCode: Int
    let visitedElementCount: Int
    let commandVCandidateCount: Int

    var summary: String {
        "stage=\(stage), axError=\(accessibilityErrorCode), visited=\(visitedElementCount), commandVCandidates=\(commandVCandidateCount)"
    }
}

enum PasteMenuItemPolicy {
    private static let commandOnlyModifiers = 0

    static func matchesCommandV(
        commandCharacter: String?,
        modifiers: Int?,
        isEnabled: Bool
    ) -> Bool {
        guard isEnabled, modifiers == commandOnlyModifiers else { return false }
        return commandCharacter?.localizedLowercase == "v"
    }
}

private enum PasteMenuActionResult {
    case performed
    case unavailable(PasteCommandDiagnostic)
    case failed(PasteCommandDiagnostic)
}

private enum PasteMenuActionPerformer {
    private static let maximumDepth = 8
    private static let maximumVisitedElements = 600

    static func performPaste(in processIdentifier: pid_t) -> PasteMenuActionResult {
        let application = AXUIElementCreateApplication(processIdentifier)
        let menuBarResult: (value: AXUIElement?, error: AXError) = attributeResult(
            kAXMenuBarAttribute as CFString,
            from: application
        )
        guard let menuBar = menuBarResult.value else {
            return .unavailable(
                diagnostic(
                    stage: "menu-bar",
                    error: menuBarResult.error,
                    visited: 0,
                    candidates: 0
                )
            )
        }

        var pending: [(element: AXUIElement, depth: Int)] = [(menuBar, 0)]
        var visitedCount = 0
        var commandVCandidateCount = 0

        while let current = pending.popLast() {
            visitedCount += 1
            guard visitedCount <= maximumVisitedElements else {
                return .unavailable(
                    diagnostic(
                        stage: "traversal-limit",
                        error: .success,
                        visited: visitedCount,
                        candidates: commandVCandidateCount
                    )
                )
            }

            let commandCharacter: String? = attribute(
                kAXMenuItemCmdCharAttribute as CFString,
                from: current.element
            )
            let modifierNumber: NSNumber? = attribute(
                kAXMenuItemCmdModifiersAttribute as CFString,
                from: current.element
            )
            let enabledNumber: NSNumber? = attribute(
                kAXEnabledAttribute as CFString,
                from: current.element
            )

            if commandCharacter?.localizedLowercase == "v" {
                commandVCandidateCount += 1
            }

            if PasteMenuItemPolicy.matchesCommandV(
                commandCharacter: commandCharacter,
                modifiers: modifierNumber?.intValue,
                isEnabled: enabledNumber?.boolValue ?? false
            ) {
                let error = AXUIElementPerformAction(
                    current.element,
                    kAXPressAction as CFString
                )
                return error == .success
                    ? .performed
                    : .failed(
                        diagnostic(
                            stage: "ax-press",
                            error: error,
                            visited: visitedCount,
                            candidates: commandVCandidateCount
                        )
                    )
            }

            guard current.depth < maximumDepth else { continue }
            let children: [AXUIElement]? = attribute(
                kAXChildrenAttribute as CFString,
                from: current.element
            )
            for child in children ?? [] {
                pending.append((child, current.depth + 1))
            }
        }

        return .unavailable(
            diagnostic(
                stage: "command-v-not-found",
                error: .success,
                visited: visitedCount,
                candidates: commandVCandidateCount
            )
        )
    }

    private static func diagnostic(
        stage: String,
        error: AXError,
        visited: Int,
        candidates: Int
    ) -> PasteCommandDiagnostic {
        PasteCommandDiagnostic(
            stage: stage,
            accessibilityErrorCode: Int(error.rawValue),
            visitedElementCount: visited,
            commandVCandidateCount: candidates
        )
    }

    private static func attributeResult<T>(
        _ name: CFString,
        from element: AXUIElement
    ) -> (value: T?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        guard error == .success, let value else { return (nil, error) }
        return (value as? T, error)
    }

    private static func attribute<T>(
        _ name: CFString,
        from element: AXUIElement
    ) -> T? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, name, &value) == .success,
            let value
        else { return nil }
        return value as? T
    }
}

@MainActor
final class PasteCoordinator {
    private static let activationPollInterval = 0.05
    private static let maximumActivationAttempts = 10
    private static let targetSettlingDelay = 0.12

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
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.targetSettlingDelay) {
                    completion?(self.performPasteCommand(in: targetApplication))
                }
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

    private func performPasteCommand(in targetApplication: NSRunningApplication) -> PasteResult {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard PasteTargetPolicy.mayPostEvent(
            expectedProcessIdentifier: targetApplication.processIdentifier,
            frontmostProcessIdentifier: frontmostPID,
            targetIsTerminated: targetApplication.isTerminated
        ) else {
            logger.info("automatic_paste_target_mismatch")
            return .copiedOnlyTargetMismatch
        }

        switch PasteMenuActionPerformer.performPaste(
            in: targetApplication.processIdentifier
        ) {
        case .performed:
            logger.info("automatic_paste_menu_action_performed")
            return .pasted
        case let .unavailable(diagnostic):
            logger.info("automatic_paste_menu_command_unavailable")
            return .copiedOnlyPasteCommandUnavailable(diagnostic)
        case let .failed(diagnostic):
            logger.error("automatic_paste_menu_action_failed")
            return .copiedOnlyPasteCommandFailed(diagnostic)
        }
    }

    func requestAccessibilityPermission() {
        // Swift 6 imports kAXTrustedCheckOptionPrompt as concurrency-unsafe
        // mutable C state. This is its documented, stable dictionary key.
        let options = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
