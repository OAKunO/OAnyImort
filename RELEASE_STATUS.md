# OAnyImort 1.1.0

Release preparation: 2026-11-12 (Asia/Shanghai).

- macOS: Universal binary (arm64 + x86_64), minimum macOS 14.0. Developer ID Application signed, Hardened Runtime enabled, secure timestamp verified. Apple notarization completed using the existing Xcode account; the exported app has a valid stapled ticket and is accepted by Gatekeeper as Notarized Developer ID. The final ZIP is verified after extraction. No new password or signing certificate was created.
- Windows: Self-contained Windows 10/11 x64 installer and ZIP, with Python, Qt and multimedia dependencies included. Distributed as an unsigned ZIP containing Setup.exe by maintainer decision. No signing service application was submitted. The actual published installer was downloaded, hash-checked, installed and UI launch-tested on a Windows Server 2025 GitHub runner. Physical Windows 10/11 hardware compatibility is not claimed.
- Validation: 16 macOS core tests and 11 Windows-source core/UI/media tests passed. Windows-source UI/media checks passed on both macOS and a Windows GitHub runner; the published installer also passed installation and packaged-runtime UI checks in workflow run 43190781261.
- Source: MIT licensed; third-party components retain their own notices and license texts. The local repository and source archive are prepared; publication uses the public OAKunO/OAnyImort repository.

The macOS package passes distribution trust checks. Windows is intentionally distributed unsigned, with no pending signing application. Physical Windows 10/11 hardware checks remain outside the completed CI validation.

macOS publication reused the existing Xcode developer account through developer-id upload and notarized export. No App-specific password is needed for this path. If Apple processing is pending, resume the same archive instead of resubmitting.
