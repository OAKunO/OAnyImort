import Foundation
import XCTest
@testable import OAnyImportCore

final class PreferencesMigrationTests: XCTestCase {
    func testMigrationPreservesNewPreferencesAndPrefersMostRecentLegacy() throws {
        let domain = "OAnyImportTests.\(UUID().uuidString)"
        let old = domain + ".old"
        let older = domain + ".older"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer {
            for name in [domain, old, older] { defaults.removePersistentDomain(forName: name) }
        }
        defaults.setPersistentDomain(["destination": "/old/media", "verify": false, "appearance": "dark", "migratedLegacyPreferences": true], forName: old)
        defaults.setPersistentDomain(["destination": "/older/media", "layout": "legacy-layout"], forName: older)
        defaults.set("light", forKey: "appearance")
        PreferencesMigration.migrate(defaults: defaults, legacyDomains: [old, older])
        XCTAssertEqual(defaults.string(forKey: "destination"), "/old/media")
        XCTAssertEqual(defaults.object(forKey: "verify") as? Bool, false)
        XCTAssertEqual(defaults.string(forKey: "appearance"), "light")
        XCTAssertEqual(defaults.string(forKey: "layout"), "legacy-layout")
        defaults.removeObject(forKey: "destination")
        PreferencesMigration.migrate(defaults: defaults, legacyDomains: [old])
        XCTAssertNil(defaults.object(forKey: "destination"))
    }
}
