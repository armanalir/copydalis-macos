import Carbon.HIToolbox
import Foundation

enum HotKeyRegistrationError: Error, Equatable {
    case installationFailed(OSStatus)
    case registrationFailed(OSStatus)
}

@MainActor
final class CarbonHotKeyRegistrar {
    private var hotKeyReference: EventHotKeyRef?
    private var handlerReference: EventHandlerRef?
    private var action: (() -> Void)?

    func register(configuration: HotKeyConfiguration, action: @escaping () -> Void) throws {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let registrar = Unmanaged<CarbonHotKeyRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                MainActor.assumeIsolated {
                    registrar.action?()
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &handlerReference
        )
        guard installStatus == noErr else {
            throw HotKeyRegistrationError.installationFailed(installStatus)
        }

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            configuration.keyCode,
            configuration.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard registerStatus == noErr else {
            unregister()
            throw HotKeyRegistrationError.registrationFailed(registerStatus)
        }
    }

    func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let handlerReference {
            RemoveEventHandler(handlerReference)
            self.handlerReference = nil
        }
        action = nil
    }

    private static var signature: OSType {
        let bytes: [UInt8] = Array("CPLY".utf8)
        return bytes.reduce(0) { ($0 << 8) | OSType($1) }
    }
}
