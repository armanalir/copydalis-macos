# Privacy Notice — Development Draft

Copydalis processes clipboard text locally to provide clipboard history.

## Data processed

- copied plain text;
- capture time;
- source application's display name and bundle identifier, when available;
- local preferences such as history capacity and appearance.

## Purpose

The data is used only to display, select, copy, and paste local clipboard history.

## Storage and retention

- Clipboard entries and source metadata are encrypted in a local SQLite database.
- The encryption key is stored in macOS Keychain as a device-only, non-synchronizing item.
- Retention is bounded by the configured history capacity.
- Clear History removes database entries and rotates the encryption key.
- The current system clipboard and copies held by macOS, destination applications, device backups, or endpoint-management products are outside Copydalis's deletion boundary.

## Transfers and network activity

V1 has no account, cloud synchronization, analytics, advertising, remote crash reporting, or network entitlement. Copydalis does not intentionally transfer clipboard data to another device or service.

## User controls

- pause or resume capture;
- choose history capacity;
- clear all history;
- quit the application;
- revoke Accessibility permission in System Settings.

## Protected content

Copydalis rejects known transient, concealed, auto-generated, and password-manager pasteboard types before requesting their text representation. No denylist can identify every sensitive value; users and organizations must still control what may be copied and whether clipboard-history software is permitted.

## Legal and organizational responsibility

This notice describes the application's technical behavior and is not legal advice. A deploying organization determines its role, lawful basis, notices, retention period, data-subject handling, records, and cross-border obligations under applicable law and policy.
