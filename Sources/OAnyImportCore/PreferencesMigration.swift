import Foundation

public enum PreferencesMigration {
    public static func migrate(
        defaults: UserDefaults = .standard,
        legacyDomains: [String] = ["com.oakuno.oanyimort", "com.oakuno.sdimport", "com.ccw.sdimport"]
    ) {
        let marker = "migratedOAnyImportPreferences"
        guard !defaults.bool(forKey: marker) else { return }
        for domain in legacyDomains {
            guard let legacy = defaults.persistentDomain(forName: domain) else { continue }
            for key in ["destination", "layout", "separateCards", "verify", "appearance"] {
                if defaults.object(forKey: key) == nil, let value = legacy[key] {
                    defaults.set(value, forKey: key)
                }
            }
        }
        defaults.set(true, forKey: marker)
    }
}
