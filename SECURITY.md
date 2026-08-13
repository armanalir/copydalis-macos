# Security Policy

## Supported versions

Copydalis is not yet production-ready. Until the first signed V1 release, the source tree is supported for development and security review only.

## Reporting a vulnerability

Do not place vulnerability details, clipboard samples, database files, Keychain material, crash dumps containing sensitive data, or exploit code in a public issue.

After the public GitHub repository is created, use GitHub Private Vulnerability Reporting. If that channel is unavailable, open a public issue containing only the words **Security contact requested** and no technical details; a private channel will then be arranged.

Include only privacy-safe information initially:

- affected version or commit;
- macOS version and CPU architecture;
- security impact category;
- whether exploitation is local or remote;
- minimal reproduction steps with synthetic, non-sensitive data.

## Security response process

1. Confirm receipt and assign a private tracking identifier.
2. Reproduce with synthetic data and classify confidentiality, integrity, and availability impact.
3. Contain the issue and assess whether release signing, keys, or artifacts are affected.
4. Add a regression test before merging the correction.
5. Review adjacent code paths and update the threat model.
6. Publish a signed corrected release and advisory when users need to act.

Response timing targets will be published once a maintainer security contact and release process exist. These targets are not an incident-notification substitute for organizations subject to KVKK, GDPR, contractual, defence-industry, or national-security obligations.

## Design commitments

- No clipboard content in logs, analytics, crash-reporting services, issue templates, or CI artifacts.
- No network or cloud entitlement in V1.
- Clipboard payload encryption before persistence.
- Non-synchronizing device-only Keychain key.
- Protected pasteboard types rejected before plaintext is read.
- Minimal third-party dependency surface.
- Regression tests for every security correction.
- Signed, notarized release artifacts with published checksums before V1.

## Out of scope for claims

The project maps controls to security and privacy frameworks but does not claim ISO/IEC 27001 certification or legal compliance. Deployment organizations must perform their own risk assessment, lawful-basis analysis, approval, retention policy, DPIA/VERBIS evaluation where applicable, and incident-response integration.
