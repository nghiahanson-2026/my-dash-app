import Foundation
import XCTest
@testable import DashProtocol

/// Loads a vector file from the copy in Tests/DashProtocolTests/Vectors.
enum Vectors {
    static func load(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> [[String: Any]] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Vectors") else {
            XCTFail("vector file \(name).json not found", file: file, line: line)
            return []
        }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let vectors = object?["vectors"] as? [[String: Any]] ?? []
        XCTAssertFalse(vectors.isEmpty, "\(name).json has no vectors", file: file, line: line)
        return vectors
    }
}

func bytes(_ hex: String, file: StaticString = #filePath, line: UInt = #line) -> [UInt8] {
    guard let result = Hex.bytes(hex) else {
        XCTFail("bad hex: \(hex)", file: file, line: line)
        return []
    }
    return result
}
