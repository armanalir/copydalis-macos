# Contributing

Copydalis handles highly sensitive clipboard data. Changes are expected to be small, reviewable, and test-backed.

## Before opening a pull request

1. Explain the user-visible change and its security/privacy impact.
2. Add normal, boundary, and failure-path tests.
3. Run `swift test`, the Xcode build, and `./Scripts/security-check.sh`.
4. Confirm that no real clipboard data, credentials, identifiers, database files, or Keychain values are present.
5. Update the threat model for new data flows, permissions, dependencies, or trust boundaries.

Do not add telemetry, analytics, network clients, cloud synchronization, dynamic code loading, shell execution, AppleScript, browser embedding, or a new dependency without an approved design and threat-model update.

Security reports must follow [SECURITY.md](SECURITY.md), not the public issue tracker.
