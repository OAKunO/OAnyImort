# OAnyImport 1.1.1

Name correction release: 2026-11-13 (Asia/Shanghai).

- Correct product spelling: OAnyImport (the 1.1.0 name omitted the p in Import). App UI, Swift modules, identifiers, installer metadata, executable names, archives, documentation, repository and website are updated together.
- Preferences migrate once from OAnyImort 1.1.0, then older SDImport settings, without overwriting existing OAnyImport preferences. Imported media remains at its existing destination.
- Local verification: 17 Swift core/migration tests and 12 Windows-source core/UI/media/migration tests passed.
- macOS: universal Developer ID signed build prepared; Apple notarization and public download verification pending.
- Windows: self-contained unsigned installer and ZIP rebuilt with corrected internal UI, launcher, archive paths and product metadata. Native Windows CI validation pending.
- Website: canonical path /project/oanyimport; /project/oanyimort and legacy download links retained as redirects. Deployment pending.

Historical 1.1.0 assets remain in their original release for reproducibility. The new version uses a new tag and new checksums.
