import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController {
    enum UpdateError: Error {
        case registrationFailed
        case removalFailed
    }

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw enabled ? UpdateError.registrationFailed : UpdateError.removalFailed
        }
    }
}
