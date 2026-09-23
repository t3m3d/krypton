import XCTest
@testable import SquirrelSounds

final class CatalogTests: XCTestCase {
    func testBundledCatalogHasUniqueIDsAndAttribution() throws {
        let animals = try Catalog.load()
        XCTAssertFalse(animals.isEmpty)
        XCTAssertEqual(Set(animals.map(\.id)).count, animals.count)
        let sounds = animals.flatMap(\.sounds)
        XCTAssertFalse(sounds.isEmpty)
        XCTAssertEqual(Set(sounds.map(\.id)).count, sounds.count)
        for sound in sounds {
            XCTAssertFalse(sound.credit.isEmpty)
            XCTAssertEqual(sound.sourceURL.scheme, "https")
            XCTAssertEqual(sound.licenseURL.scheme, "https")
        }
    }
}
