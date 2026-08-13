# Copydalis

Copydalis is a private, keyboard-first clipboard history app for macOS. Its primary interaction recreates Flycut's release-to-paste workflow with a modern Swift/AppKit implementation:

1. press and hold the configured shortcut (default `Shift-Command-V`);
2. move through history with the arrow keys;
3. release the modifier keys to paste the selected entry exactly once.

Repeated presses of `V` do not navigate the history.

> [!WARNING]
> Copydalis is pre-release software. It has not yet completed manual interaction, penetration, notarization, or managed-enterprise testing. Do not deploy it on classified, export-controlled, production, or otherwise regulated systems without written organizational authorization and security review.

## Current development status

The first implementation slice includes:

- menu-bar-only AppKit application;
- configurable global shortcut, menu count, popup row count, capacity, behavior, and appearance;
- centered nonactivating multi-row history panel;
- arrow navigation, Escape cancellation, Return commit, and modifier-release commit;
- local text-only clipboard monitoring and protected-type filtering;
- encrypted SQLite history using AES-256-GCM;
- a non-synchronizing, device-only Keychain key;
- HMAC-SHA-256 duplicate lookup;
- crypto-erasure key rotation on Clear History;
- no iCloud, account, telemetry, analytics, crash SDK, network feature, or runtime dependency;
- Developer ID distribution profile with Hardened Runtime and no App Sandbox, required for the release-to-paste Accessibility workflow;
- Swift 6 strict concurrency and automated security/behavior tests.

## Security model

Clipboard data is highly sensitive. Copydalis encrypts every persisted entry before SQLite receives it. The encryption key is stored in macOS Keychain with `WhenUnlockedThisDeviceOnly`, and plaintext is prohibited from application logs.

Encryption at rest does not protect text while it is in the system clipboard, application memory, the destination application, external backups, or from another process running with equivalent user privileges. FileVault, a secured login account, current OS patches, and endpoint policy remain required.

Copydalis is distributed outside App Sandbox because the tested sandboxed build could not obtain the Accessibility trust required to synthesize the final Command-V. The application contains no network functionality and CI rejects known networking APIs/frameworks, but without App Sandbox this is a reviewed code property rather than an operating-system network boundary.

See [SECURITY.md](SECURITY.md), [PRIVACY.md](PRIVACY.md), and [Documentation/THREAT_MODEL.md](Documentation/THREAT_MODEL.md).

## Requirements

- macOS 14 or newer
- Xcode 26.6 for the currently verified development build
- XcodeGen for regenerating `Copydalis.xcodeproj`

## Build

```sh
xcodegen generate
xcodebuild -project Copydalis.xcodeproj \
  -scheme Copydalis \
  -configuration Debug \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Test

```sh
swift test
./Scripts/security-check.sh
```

The Xcode unit-test target contains the same tests. A standalone Swift package is also provided so core tests can run without launching a clipboard-monitoring application.

### Synthetic interaction mode

The Debug build accepts `--interaction-test-mode`. In this mode Copydalis does not start clipboard monitoring and does not open its history database or Keychain key. It displays three fixed synthetic records for manual shortcut/popup testing. Selecting a record still writes that synthetic value to the system clipboard and may synthesize Command-V, so run it only with explicit user consent and in a disposable test document.

## Distribution

Public V1 distribution is planned through signed and notarized GitHub Releases. The final bundle identifier, GitHub owner, Developer ID signing identity, release checksums, SBOM, and manual security verification must be settled before the first release.

## License

MIT. See [LICENSE](LICENSE).
