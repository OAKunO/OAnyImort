# OAnyImort 1.1.0

Release preparation: 2026-11-12 (Asia/Shanghai).

- macOS: Universal binary (arm64 + x86_64), minimum macOS 14.0. Developer ID Application signed, Hardened Runtime enabled, secure timestamp verified. Apple notarization completed using the existing Xcode account; the exported app has a valid stapled ticket and is accepted by Gatekeeper as Notarized Developer ID. The final ZIP is verified after extraction. No new password or signing certificate was created.
- Windows: Self-contained Windows 10/11 x64 installer and ZIP, with Python, Qt and multimedia dependencies included. No trusted Authenticode certificate is configured. Installation on a physical Windows computer is not yet verified.
- Validation: 16 macOS core tests and 11 Windows-source core/UI/media tests passed. Windows-source UI/media checks ran on macOS with the same Qt version; this is not a Windows installation test.
- Source: MIT licensed; third-party components retain their own notices and license texts. The local repository and source archive are prepared; publication uses the public OAKunO/OAnyImort repository.

The macOS package passes distribution trust checks. Windows trusted code signing and physical Windows installation validation remain pending. Windows-source tests on macOS are not a Windows installation test.

macOS publication reuses the existing Xcode developer account through `scripts/release-macos.sh`. No App-specific password is needed for this path. If Apple processing is pending, resume the same archive instead of resubmitting.
