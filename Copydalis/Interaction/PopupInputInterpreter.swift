import Foundation

enum PopupInputCommand: Equatable, Sendable {
    case moveOlder
    case moveNewer
    case selectNewest
    case selectOldest
    case pageOlder
    case pageNewer
    case commit
    case cancel
    case ignore
    case passThrough
}

struct PopupInputInterpreter: Sendable {
    static func command(
        forKeyCode keyCode: UInt16,
        horizontalArrowAliases: Bool
    ) -> PopupInputCommand {
        switch keyCode {
        case 125:
            .moveOlder
        case 126:
            .moveNewer
        case 124 where horizontalArrowAliases:
            .moveOlder
        case 123 where horizontalArrowAliases:
            .moveNewer
        case 115:
            .selectNewest
        case 119:
            .selectOldest
        case 121:
            .pageOlder
        case 116:
            .pageNewer
        case 36, 76:
            .commit
        case 53:
            .cancel
        case 9:
            .ignore
        default:
            .passThrough
        }
    }
}

enum PopupAppearanceConstraints: Sendable {
    static let minimumOpacity = 0.40
    static let maximumOpacity = 1.00
    static let defaultOpacity = 0.92

    static func clampOpacity(_ value: Double) -> Double {
        min(max(value, minimumOpacity), maximumOpacity)
    }
}
