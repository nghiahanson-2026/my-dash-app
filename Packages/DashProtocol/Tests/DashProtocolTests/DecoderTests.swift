import XCTest
@testable import DashProtocol

final class DecoderTests: XCTestCase {
    private func decodeOne(_ hex: String) -> FrameDecoder.Event? {
        var decoder = FrameDecoder()
        let events = decoder.feed(bytes(hex))
        return events.count == 1 ? events[0] : nil
    }

    /// Decode every bike-to-phone vector: magic, length and CRC are checked by the decoder.
    func testEveryBikeVectorDecodes() throws {
        for v in try Vectors.load("link-a-commands") {
            let id = v["id"] as! String
            let hex = (v["input"] as! [String: Any])["frame_hex"] as! String
            let e = v["expect"] as! [String: Any]
            guard case .frame(let frame)? = decodeOne(hex) else { XCTFail("did not decode: \(id)"); continue }
            XCTAssertEqual(Int(frame.command), e["command"] as! Int, id)
            XCTAssertEqual(Int(frame.flag), e["flag"] as! Int, id)
            XCTAssertEqual(Hex.string(frame.payload), e["payload_hex"] as! String, id)
            checkMeaning(id: id, frame: frame, means: e["means"] as! [String: Any])
        }
    }

    private func checkMeaning(id: String, frame: Frame, means: [String: Any]) {
        let message = BikeMessage.parse(frame)
        switch id {
        case "bike-66":
            XCTAssertEqual(message, .serial(means["serial"] as! String), id)
        case "bike-82":
            XCTAssertEqual(message, .authenticated(means["authenticated"] as! Bool), id)
        case "bike-83":
            let screen = means["screen"] as! [Int]
            XCTAssertEqual(message, .challenge(
                part: means["part_number"] as! String,
                key: bytes(means["key_hex"] as! String),
                screen: ScreenSize(width: screen[0], height: screen[1])), id)
        case "bike-55":
            XCTAssertEqual(message, .showFrames, id)
        case "bike-56":
            XCTAssertEqual(message, .pause, id)
        case "bike-65":
            XCTAssertEqual(message, .speed(means["speed_kmh"] as! Int, isMph: false), id)
        case "bike-51":
            XCTAssertEqual(message, .up, id)
        case "bike-52":
            XCTAssertEqual(message, .down, id)
        case "bike-80":
            XCTAssertEqual(message, .ack(frameID: UInt16(means["ack_frame_id"] as! Int)), id)
        default:
            XCTFail("no meaning check written for vector \(id)")
        }
    }

    func testBytesArriveOneAtATimeWithGarbageInFront() throws {
        let v = try Vectors.load("link-a-commands")[2]   // bike-83
        let frame = bytes((v["input"] as! [String: Any])["frame_hex"] as! String)
        var decoder = FrameDecoder()
        var events: [FrameDecoder.Event] = []
        for byte in [0x00, 0x6E, 0x41] + frame {       // junk that even starts like the magic
            events += decoder.feed([byte])
        }
        XCTAssertEqual(events.count, 1)
        guard case .frame(let decoded)? = events.first else { return XCTFail("no frame") }
        XCTAssertEqual(decoded.command, 83)
    }

    func testTwoFramesInOneChunk() throws {
        let vectors = try Vectors.load("link-a-commands")
        let a = bytes((vectors[3]["input"] as! [String: Any])["frame_hex"] as! String)
        let b = bytes((vectors[7]["input"] as! [String: Any])["frame_hex"] as! String)
        var decoder = FrameDecoder()
        XCTAssertEqual(decoder.feed(a + b).count, 2)
    }

    func testBadCRCIsReportedAndSkipped() throws {
        let v = try Vectors.load("link-a-commands")[0]   // bike-66
        var frame = bytes((v["input"] as! [String: Any])["frame_hex"] as! String)
        frame[frame.count - 1] ^= 0xFF                      // corrupt the payload
        var decoder = FrameDecoder()
        let events = decoder.feed(frame)
        XCTAssertEqual(events, [.badCRC(command: 66)])
    }

    func testAbsurdLengthIsSkipped() {
        // A magic followed by a length of 0xFFFFFFFF must not make the decoder wait for 4 GB.
        var decoder = FrameDecoder()
        let junk: [UInt8] = Frame.magic + [0x01, 0x03, 0x42, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0, 0, 0, 0]
        XCTAssertEqual(decoder.feed(junk), [])
        let v = try! Vectors.load("link-a-commands")[0]
        let good = bytes((v["input"] as! [String: Any])["frame_hex"] as! String)
        XCTAssertEqual(decoder.feed(good).count, 1, "decoder recovers and finds the next real frame")
    }
}
