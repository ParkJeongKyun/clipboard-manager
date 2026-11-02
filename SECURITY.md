# Security Policy

Clipboard Manager handles everything you copy, so security reports are taken seriously.

## Supported versions

Only the latest release receives fixes. The app updates itself from GitHub Releases; please update before reporting.

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report privately through GitHub: **Security → Report a vulnerability** on this repository
(<https://github.com/ParkJeongKyun/clipboard-manager/security/advisories/new>).

Please include the app version, macOS version, steps to reproduce and the impact you expect.
You should get a response within 7 days.

## Scope

In scope, for example:

- Clipboard contents leaking outside the encrypted history (logs, temporary files, other processes)
- Recording content that should be ignored (confidential pasteboard types, ignored apps)
- Bypassing update verification (checksum, signature, bundle identifier or version checks)
- Issues in `install.sh` or the release workflow

Out of scope: anything that requires an attacker who already runs code as your user, or Gatekeeper warnings caused by the app not being notarized.
