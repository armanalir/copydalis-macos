import AppKit
import Carbon.HIToolbox

struct HotKeyConfiguration: Equatable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let displayName: String

    static let defaultShortcut = HotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(cmdKey | shiftKey),
        displayName: "⇧⌘V"
    )

    static func from(event: NSEvent) -> HotKeyConfiguration? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty else { return nil }

        var carbonFlags: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { carbonFlags |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { carbonFlags |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { carbonFlags |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { carbonFlags |= UInt32(cmdKey); symbols += "⌘" }

        let key = (event.charactersIgnoringModifiers ?? "")
            .uppercased()
            .prefix(1)
        guard !key.isEmpty else { return nil }
        return HotKeyConfiguration(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: carbonFlags,
            displayName: symbols + key
        )
    }
}
