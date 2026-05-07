# Security Findings - Whisper Verses

**Review Date**: 2026-03-01
**Reviewer**: Alice (automated security review)
**Status**: Initial review

**Severity Summary**: 1 Critical, 1 High, 3 Medium, 3 Low

---

## Findings Table

| ID | Severity | Finding | File:Line | Status |
|----|----------|---------|-----------|--------|
| WV-01 | CRITICAL | Command injection in update trampoline | UpdateService.swift:225-236 | Open |
| WV-02 | HIGH | No signature verification of downloaded updates | UpdateService.swift:200-219 | Open |
| WV-03 | MEDIUM | No certificate pinning for update channel | UpdateService.swift:200-201 | Open |
| WV-04 | MEDIUM | ProPresenter API uses plaintext HTTP | OnboardingView.swift | Open |
| WV-05 | MEDIUM | Debug log to world-readable /tmp | ThreadSafeAudioProcessor.swift | Open |
| WV-06 | LOW | Console logging of user input | Various | Open |
| WV-07 | LOW | WhisperKit pinned to main branch | Package.swift | Open |
| WV-08 | LOW | Version string from GitHub API not validated before use in trampoline | UpdateService.swift:225 | Open |

---

## Detailed Findings

### WV-01: Command injection in update trampoline (CRITICAL)

**File**: `WhisperVerses/Services/Update/UpdateService.swift:225-236`

The self-update mechanism creates a bash trampoline script that interpolates file paths directly into shell commands without escaping or quoting for shell metacharacters:

```swift
let script = """
#!/bin/bash
while kill -0 \(pid) 2>/dev/null; do
    sleep 0.5
done
rm -rf "\(currentAppURL.path)"
mv "\(newAppURL.path)" "\(currentAppURL.path)"
codesign --force --deep --sign - "\(currentAppURL.path)"
open "\(currentAppURL.path)"
rm -rf "\(tempDir.path)"
"""
```

If the app is installed at a path containing shell metacharacters (e.g., a directory with `$()` or backticks in the name), arbitrary commands could be executed. While the `currentAppURL` comes from `Bundle.main.bundleURL` (user-controlled install location), the `newAppURL` and `tempDir` are constructed from temp directories which are safer. The primary risk is from user-chosen install locations.

**Impact**: Arbitrary command execution during update process.
**Remediation**: POSIX-quote all interpolated paths (replace `'` with `'\''` and wrap in single quotes), or use `Process()` with argument arrays instead of a shell script.

---

### WV-02: No signature verification of downloaded updates (HIGH)

**File**: `UpdateService.swift:200-219`

The app downloads a zip from GitHub Releases and applies it without verifying any cryptographic signature. An attacker who can compromise the GitHub release, perform a MitM attack, or modify the download in transit could inject malicious code.

**Impact**: Malicious update could replace the entire application.
**Remediation**: Implement EdDSA signature verification of downloaded archives (Sparkle provides this), or migrate to Sparkle for the update mechanism entirely.

---

### WV-03: No certificate pinning for update channel (MEDIUM)

**File**: `UpdateService.swift:200-201`

While the update downloads use HTTPS via GitHub, there is no certificate pinning. A compromised or rogue CA could issue a certificate to intercept the connection.

**Impact**: MitM attack on update channel with a forged certificate.
**Remediation**: Consider certificate pinning for the GitHub API domain, or migrate to Sparkle which provides its own signature-based verification.

---

### WV-04: ProPresenter API uses plaintext HTTP (MEDIUM)

**File**: `OnboardingView.swift`

The connection to ProPresenter uses HTTP on the local network. While ProPresenter only supports HTTP for its REST API, any data exchanged (presentation content, slide text) is transmitted in cleartext on the LAN.

**Impact**: Network eavesdropping of presentation content on the local network.
**Remediation**: Document this as an accepted risk since ProPresenter does not support HTTPS. Ensure the app is only used on trusted networks.

---

### WV-05: Debug log to world-readable /tmp (MEDIUM)

**File**: `ThreadSafeAudioProcessor.swift`

Debug logging writes to `/tmp`, which is world-readable on macOS. Log entries may contain transcription fragments or operational details.

**Impact**: Information disclosure of transcription data via temp files.
**Remediation**: Log to `~/Library/Logs/` or Application Support directory with appropriate permissions, or remove debug logging in release builds.

---

### WV-06: Console logging of user input (LOW)

**File**: Various

Console log statements may include fragments of detected verses and transcription output. While `os_log` and `print` output is only accessible to users with console access, it represents information leakage.

**Impact**: Minor information disclosure through system console.
**Remediation**: Remove or reduce verbosity of logging in release builds.

---

### WV-07: WhisperKit pinned to main branch (LOW)

**File**: `Package.swift`

WhisperKit dependency is pinned to `branch: main` rather than a specific version tag. This means builds are not reproducible and could pull in breaking or malicious changes.

**Impact**: Supply chain risk from unpinned dependency.
**Remediation**: Pin to a specific release tag or commit hash.

---

### WV-08: Version string from GitHub API not validated (LOW)

**File**: `UpdateService.swift:225`

The version tag from the GitHub API response is used in the trampoline script and file paths without regex validation. If the GitHub API response were tampered with, a malicious version string could contribute to path manipulation.

**Impact**: Path manipulation via crafted version string (requires GitHub API compromise).
**Remediation**: Validate version string format with regex `^v\d+\.\d+\.\d+$` before use.

---

## Security Posture Assessment

Whisper Verses is a local-only audio transcription app with a narrow attack surface. The primary concern is the self-update trampoline mechanism which has a command injection vulnerability (WV-01) and lacks signature verification (WV-02). The ProPresenter integration uses HTTP but this is a limitation of the ProPresenter API. The app does not handle sensitive user data beyond transcription text.

**Overall Risk**: MEDIUM - The critical finding is in the update mechanism which only runs during updates and requires specific path conditions to exploit. The app's normal operation has a low attack surface.

---

## Remediation Priority

1. **WV-01** (CRITICAL) - Fix path quoting in trampoline script
2. **WV-02** (HIGH) - Add signature verification or migrate to Sparkle
3. **WV-05** (MEDIUM) - Move debug logs out of /tmp
4. **WV-03** (MEDIUM) - Consider certificate pinning or Sparkle migration
5. **WV-04** (MEDIUM) - Document HTTP as accepted risk
6. **WV-07** (LOW) - Pin WhisperKit to release tag
7. **WV-08** (LOW) - Add version string validation
8. **WV-06** (LOW) - Reduce release-build logging
