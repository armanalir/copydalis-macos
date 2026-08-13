import Foundation
import OSLog

struct PrivacySafeLogger: Sendable {
    private let logger: Logger

    init(category: String) {
        logger = Logger(subsystem: "com.copydalis.app", category: category)
    }

    func info(_ event: StaticString) {
        logger.info("\(event, privacy: .public)")
    }

    func error(_ event: StaticString, code: Int = 0) {
        logger.error("\(event, privacy: .public) code=\(code, privacy: .public)")
    }

    func metric(_ event: StaticString, count: Int) {
        logger.info("\(event, privacy: .public) count=\(count, privacy: .public)")
    }
}
