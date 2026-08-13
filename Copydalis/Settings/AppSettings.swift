import AppKit
import Foundation

enum AppAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum MenuSelectionAction: String, CaseIterable, Sendable {
    case paste
    case copyOnly
}

@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let historyCapacity = "historyCapacity"
        static let menuItemCount = "menuItemCount"
        static let popupRowCount = "popupRowCount"
        static let appearance = "appearance"
        static let capturePaused = "capturePaused"
        static let wraparound = "wraparound"
        static let removeExactDuplicates = "removeExactDuplicates"
        static let movePastedToNewest = "movePastedToNewest"
        static let horizontalArrowAliases = "horizontalArrowAliases"
        static let menuSelectionAction = "menuSelectionAction"
        static let showSourceMetadata = "showSourceMetadata"
        static let hotKeyKeyCode = "hotKeyKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let hotKeyDisplayName = "hotKeyDisplayName"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.historyCapacity: 100,
            Key.menuItemCount: 10,
            Key.popupRowCount: 7,
            Key.appearance: AppAppearance.system.rawValue,
            Key.capturePaused: false,
            Key.wraparound: false,
            Key.removeExactDuplicates: false,
            Key.movePastedToNewest: false,
            Key.horizontalArrowAliases: true,
            Key.menuSelectionAction: MenuSelectionAction.paste.rawValue,
            Key.showSourceMetadata: true,
            Key.hotKeyKeyCode: Int(HotKeyConfiguration.defaultShortcut.keyCode),
            Key.hotKeyModifiers: Int(HotKeyConfiguration.defaultShortcut.carbonModifiers),
            Key.hotKeyDisplayName: HotKeyConfiguration.defaultShortcut.displayName
        ])
    }

    var historyCapacity: Int {
        get { clamp(defaults.integer(forKey: Key.historyCapacity), to: 10...9_999) }
        set { defaults.set(clamp(newValue, to: 10...9_999), forKey: Key.historyCapacity) }
    }

    var menuItemCount: Int {
        get { min(clamp(defaults.integer(forKey: Key.menuItemCount), to: 1...30), historyCapacity) }
        set { defaults.set(min(clamp(newValue, to: 1...30), historyCapacity), forKey: Key.menuItemCount) }
    }

    var popupRowCount: Int {
        get { clamp(defaults.integer(forKey: Key.popupRowCount), to: 3...20) }
        set { defaults.set(clamp(newValue, to: 3...20), forKey: Key.popupRowCount) }
    }

    var appearance: AppAppearance {
        get { AppAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    var capturePaused: Bool {
        get { defaults.bool(forKey: Key.capturePaused) }
        set { defaults.set(newValue, forKey: Key.capturePaused) }
    }

    var wraparound: Bool {
        get { defaults.bool(forKey: Key.wraparound) }
        set { defaults.set(newValue, forKey: Key.wraparound) }
    }

    var removeExactDuplicates: Bool {
        get { defaults.bool(forKey: Key.removeExactDuplicates) }
        set { defaults.set(newValue, forKey: Key.removeExactDuplicates) }
    }

    var movePastedToNewest: Bool {
        get { defaults.bool(forKey: Key.movePastedToNewest) }
        set { defaults.set(newValue, forKey: Key.movePastedToNewest) }
    }

    var horizontalArrowAliases: Bool {
        get { defaults.bool(forKey: Key.horizontalArrowAliases) }
        set { defaults.set(newValue, forKey: Key.horizontalArrowAliases) }
    }

    var showSourceMetadata: Bool {
        get { defaults.bool(forKey: Key.showSourceMetadata) }
        set { defaults.set(newValue, forKey: Key.showSourceMetadata) }
    }

    var menuSelectionAction: MenuSelectionAction {
        get { MenuSelectionAction(rawValue: defaults.string(forKey: Key.menuSelectionAction) ?? "") ?? .paste }
        set { defaults.set(newValue.rawValue, forKey: Key.menuSelectionAction) }
    }

    var hotKey: HotKeyConfiguration {
        get {
            let keyCode = defaults.integer(forKey: Key.hotKeyKeyCode)
            let modifiers = defaults.integer(forKey: Key.hotKeyModifiers)
            let displayName = defaults.string(forKey: Key.hotKeyDisplayName) ?? ""
            guard keyCode >= 0, modifiers > 0, !displayName.isEmpty else {
                return .defaultShortcut
            }
            return HotKeyConfiguration(
                keyCode: UInt32(keyCode),
                carbonModifiers: UInt32(modifiers),
                displayName: displayName
            )
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Key.hotKeyKeyCode)
            defaults.set(Int(newValue.carbonModifiers), forKey: Key.hotKeyModifiers)
            defaults.set(newValue.displayName, forKey: Key.hotKeyDisplayName)
        }
    }

    private func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
