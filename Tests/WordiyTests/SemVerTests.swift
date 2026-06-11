import XCTest

@testable import Wordiy

final class SemVerTests: XCTestCase {

    func testHigher() {
        XCTAssertEqual(SemVer.higher("1.0.0", "1.1.0"), "1.1.0")
        XCTAssertEqual(SemVer.higher("1.1.0", "1.0.0"), "1.1.0")
        XCTAssertEqual(SemVer.higher("v1.0.0", "1.1.0"), "1.1.0")  // tolerates leading v
        XCTAssertEqual(SemVer.higher("1.9.0", "1.10.0"), "1.10.0")  // numeric, not lexical
        XCTAssertEqual(SemVer.higher("2.0", "1.9.9"), "2.0")  // differing lengths
    }

    func testEqualReturnsFirst() {
        XCTAssertEqual(SemVer.higher("1.1.0", "1.1.0"), "1.1.0")
        XCTAssertEqual(SemVer.compare("1.0.0", "v1.0.0"), .orderedSame)
    }
}
