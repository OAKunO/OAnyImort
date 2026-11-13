# OAnyImport 1.1.1

Released: 2026-11-13 (Asia/Shanghai).

- macOS 14+: universal Apple silicon / Intel ZIP. Developer ID signed, Apple notarized, with a valid stapled ticket and Gatekeeper acceptance.
- Windows 10/11 x64: unsigned, self-contained ZIP containing Setup.exe and the Python, Qt and media runtime. The actual published installer passed checksum verification, silent installation and packaged-runtime UI launch checks on Windows Server 2025 in GitHub Actions run 43371390762.
- Validation: 17 Swift core/preferences tests and 12 Windows-source core/UI/media/preferences tests passed. Public Mac, Windows and source ZIP downloads were verified by SHA-256 and archive integrity.
- Preferences: existing destination, appearance and import settings are preserved on upgrade; current preferences take priority.
- Website: https://oakuno.com/project/oanyimport
- Source: https://github.com/OAKunO/OAnyImport

Windows is distributed unsigned. Physical Windows 10/11 hardware checks are not part of the completed CI validation.
