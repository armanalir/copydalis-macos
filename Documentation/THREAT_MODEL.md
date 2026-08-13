# Copydalis Threat Model

Status: Initial V1 model; review before every release.

## Assets

- clipboard plaintext and source metadata;
- history encryption key;
- encrypted history database and WAL files;
- user preferences;
- application signing identity and release artifacts;
- Accessibility permission and global-shortcut trust.

## Trust boundaries

```text
Source app -> macOS pasteboard -> Copydalis process -> encrypted SQLite
                                      |
                                      +-> macOS Keychain
                                      |
Selected target app <- synthetic paste+
```

## Primary threats

| Threat | Control | Residual limitation |
|---|---|---|
| Offline database theft | AES-256-GCM; device-only Keychain key; FileVault recommendation | Logged-in or equivalent-privilege attacker may access Keychain/process memory |
| Guessing common clipboard values from hashes | Domain-separated HMAC-SHA-256 | Live process can compute comparisons while unlocked |
| Database tampering | Authenticated encryption; strict decode and size limits | Availability loss remains possible if files are deleted or corrupted |
| Password/sensitive-text retention | Protected-type filter, pause, bounded capacity, clear | Applications may omit protected-type markers |
| Plaintext logging | Fixed privacy-safe event identifiers; source policy checks | OS or third-party tools may independently observe pasteboard/processes |
| Wrong-target paste | Capture intended app, one-shot session, fail-closed paths, manual matrix | Focus can change at the OS/user boundary and requires interaction testing |
| Persistent key monitoring | Carbon hotkey registration and popup-local event handling | Accessibility is still required for final synthetic paste |
| Oversized/copy-storm denial of service | 10 MiB entry cap, bounded history, serialized actor/database transactions | System pasteboard itself is outside Copydalis control |
| Supply-chain compromise | No runtime dependencies in current implementation, code review, CI, signed releases | Xcode/macOS/build infrastructure remain trusted dependencies |
| Incomplete deletion on SSD/backups | Key rotation provides crypto-erasure boundary | System clipboard and external backups are outside application control |

## Fail-closed requirements

- Missing Keychain key access: do not start clipboard monitoring.
- Authentication or decode failure: reject the affected row and never display attacker-controlled partial plaintext.
- Missing Accessibility permission: copy only; do not crash or repeatedly prompt.
- Ambiguous selection state or watchdog expiry: cancel without paste.
- Shortcut registration conflict: restore the last working shortcut.
- Clear-history key-rotation failure: retain history and report failure; never claim it was cleared.

## Verification evidence

Automated tests cover encryption round-trip, nonce uniqueness, tamper/wrong-key rejection, keyed digests, plaintext absence in SQLite/WAL, key rotation, database ordering/capacity/deduplication, protected-type filtering, and exactly-once selection outcomes.

Manual evidence remains required for Accessibility, keyboard layouts, focus changes, secure input, lock/unlock, full-screen apps, Spaces, multiple displays, MDM/EDR coexistence, signing, notarization, and sandbox compatibility.
