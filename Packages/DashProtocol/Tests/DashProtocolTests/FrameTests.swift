import XCTest
@testable import DashProtocol

final class FrameTests: XCTestCase {
    /// Encode every phone-to-bike vector byte for byte.
    func testEveryFrameVectorEncodes() throws {
        for v in try Vectors.load("frames") {
            let id = v["id"] as! String
            let i = v["input"] as! [String: Any]
            let frame = Frame(
                direction: UInt8(i["direction"] as! Int),
                command: UInt8(i["command"] as! Int),
                flag: UInt8(i["flag"] as! Int),
                payload: bytes(i["payload_hex"] as! String))
            let want = bytes((v["expect"] as! [String: Any])["frame_hex"] as! String)
            XCTAssertEqual(Hex.string(frame.encoded()), Hex.string(want), "frame vector \(id)")
        }
    }

    /// The LinkA builders must produce exactly the vector frames (not just the raw encoder).
    func testBuildersMatchVectors() throws {
        let builders: [String: Frame] = [
            "nav-state-2": LinkA.navigationState(navigating: false),
            "init-31": LinkA.init31(),
            "home-flag-10": LinkA.homeSaved(false),
            "empty-label-14": LinkA.rearmButtons(),
            "work-flag-11": LinkA.workSaved(false),
            "init-13": LinkA.init13(),
            "road-name-3": LinkA.bottomBar("L\u{00EA} L\u{1EE3}i"),
            "road-clear-3": LinkA.bottomBar(""),
            "speed-limit-50-17": LinkA.speedLimit(50),
            "speed-limit-clear-17": LinkA.speedLimit(nil),
            "init-12": LinkA.init12(),
            "pause-ack-20": LinkA.pauseAck(),
            "challenge-response-84": LinkA.challengeResponse(key: [0x44, 0x34, 0x0E, 0x0A]),
            "hello-81": LinkA.hello()[0],
            "hello-33": LinkA.hello()[1],
        ]
        var seen = Set<String>()
        for v in try Vectors.load("frames") {
            let id = v["id"] as! String
            guard let built = builders[id] else { continue }
            seen.insert(id)
            let want = bytes((v["expect"] as! [String: Any])["frame_hex"] as! String)
            XCTAssertEqual(Hex.string(built.encoded()), Hex.string(want), "builder for \(id)")
        }
        XCTAssertEqual(seen, Set(builders.keys), "every builder must be matched to a vector")
    }

    func testBottomBarIsCutOnACharacterBoundary() {
        // 100 x "ợ" = 300 bytes (3 each): the cut must land on a whole character, at most 144 bytes.
        let frame = LinkA.bottomBar(String(repeating: "\u{1EE3}", count: 100))
        XCTAssertEqual(frame.payload.count, 144)
        XCTAssertNotNil(String(bytes: frame.payload, encoding: .utf8))
        XCTAssertEqual(frame.flag, 1)
    }

    func testMapFrameLayoutAndGuards() {
        let jpeg = [UInt8](repeating: 0xAB, count: 5000)
        let frame = LinkA.mapFrame(id: 0x0102, jpeg: jpeg)!
        XCTAssertEqual(frame.command, 0)
        XCTAssertEqual(frame.flag, 1)
        XCTAssertEqual(Array(frame.payload.prefix(3)), [0x03, 0x02, 0x01])   // mode 3, id u16 LE
        XCTAssertEqual(frame.payload.count, 3 + 5000)
        XCTAssertNil(LinkA.mapFrame(id: 1, jpeg: [UInt8](repeating: 0, count: 2048)), "too small to be safe")
        XCTAssertNil(LinkA.mapFrame(id: 0, jpeg: jpeg), "frame ids start at 1")
    }
}
