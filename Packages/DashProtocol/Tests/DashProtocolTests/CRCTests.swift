import XCTest
@testable import DashProtocol

final class CRCTests: XCTestCase {
    func testEveryCRCVector() throws {
        for v in try Vectors.load("crc") {
            let id = v["id"] as! String
            let input = (v["input"] as! [String: Any])["hex"] as! String
            let expect = (v["expect"] as! [String: Any])["crc32_mpeg2"] as! String
            let want = UInt32(expect.dropFirst(2), radix: 16)!
            XCTAssertEqual(CRC32MPEG2.checksum(bytes(input)), want, "crc vector \(id)")
        }
    }
}
