import XCTest
@testable import DashProtocol

final class HandshakeTests: XCTestCase {
    private func summary(_ frames: [Frame]) -> [String] {
        frames.map { "\($0.command)/\($0.flag)/\(Hex.string($0.payload))" }
    }

    /// Feed each bike frame to the session; after it, the phone must have sent exactly `must_send`.
    func testNmaxTurboSession() throws {
        let vector = try Vectors.load("handshake-nmax-turbo")[0]
        let steps = (vector["input"] as! [String: Any])["steps"] as! [[String: Any]]
        var session = DashSession()
        var decoder = FrameDecoder()
        var pending: [Frame] = []
        var events: [SessionEvent] = []
        var clock: TimeInterval = 100

        for (index, step) in steps.enumerated() {
            let note = step["note"] as? String ?? (step["then"] as? String ?? "")
            if step["from"] as! String == "bike" {
                XCTAssertTrue(pending.isEmpty, "step \(index): the phone sent something the vector does not expect before '\(note)': \(summary(pending))")
                guard case .frame(let frame)? = decoder.feed(bytes(step["frame_hex"] as! String)).first else {
                    return XCTFail("step \(index): bike frame did not decode")
                }
                let out = session.receive(frame, now: clock)
                pending = out.send
                events += out.events
                clock += 0.1
            } else {
                let want = (step["must_send"] as! [[String: Any]]).map {
                    "\($0["command"] as! Int)/\($0["flag"] as! Int)/\($0["payload_hex"] as! String)"
                }
                XCTAssertEqual(summary(pending), want, "step \(index) (after: \(note))")
                pending = []
            }
        }
        XCTAssertTrue(pending.isEmpty)

        let screen = (vector["expect"] as! [String: Any])["screen"] as! [Int]
        XCTAssertTrue(events.contains(.screen(ScreenSize(width: screen[0], height: screen[1]))))
        XCTAssertTrue(events.contains(.startStreaming))
        XCTAssertTrue(events.contains(.button(.up)))
    }

    // MARK: Behaviour the vectors do not cover but the docs require

    private func frame(_ hex: String) -> Frame {
        var decoder = FrameDecoder()
        guard case .frame(let f)? = decoder.feed(bytes(hex)).first else { fatalError("bad frame hex") }
        return f
    }
    private let serial66 = "6E 41 6C 40 01 03 42 0A 00 00 00 00 22 E3 16 18 30 30 30 30 30 30 30 30 30 30"
    private let auth82 = "6E 41 6C 40 01 03 52 02 00 00 00 00 63 0D BF 37 01 00"
    private let challenge83 = "6E 41 6C 40 01 03 53 10 00 00 00 01 AD 20 B5 0B 3A 3A 3C 27 48 39 33 3F 38 27 3A 3B 4E 3E 04 00"
    private let show55 = "6E 41 6C 40 01 01 37 02 00 00 00 00 2E 00 08 07 01 00"
    private let pause56 = "6E 41 6C 40 01 03 38 02 00 00 00 00 F7 42 5A 9F 0B 00"
    private let ack80 = "6E 41 6C 40 01 03 50 02 00 00 00 00 C3 9F 33 07 50 01"

    func testInitFallbackTwoSecondsAfterFirst82() {
        var s = DashSession()
        _ = s.receive(frame(serial66), now: 0)
        XCTAssertTrue(s.receive(frame(auth82), now: 10).send.isEmpty, "an 82 before 83 does not trigger the init")
        XCTAssertTrue(s.tick(now: 11.9).send.isEmpty)
        XCTAssertEqual(s.tick(now: 12.0).send.count, 9, "init sequence is 9 frames")
        XCTAssertTrue(s.tick(now: 20).send.isEmpty, "init is sent only once")
    }

    func testRepeated83StartsOver() {
        var s = DashSession()
        _ = s.receive(frame(serial66), now: 0)
        _ = s.receive(frame(challenge83), now: 1)
        XCTAssertEqual(s.receive(frame(auth82), now: 2).send.count, 9)
        // the dash restarts the handshake: a new 83, then an 82 sends the init again
        _ = s.receive(frame(challenge83), now: 3)
        XCTAssertEqual(s.receive(frame(auth82), now: 4).send.count, 9)
    }

    func testOneMapFrameInFlightThenAck() {
        var s = DashSession()
        let jpeg = [UInt8](repeating: 0x11, count: 6000)
        XCTAssertNil(s.makeMapFrame(jpeg: jpeg, now: 0), "nothing before the rider presses Home")
        _ = s.receive(frame(show55), now: 1)
        let first = s.makeMapFrame(jpeg: jpeg, now: 2)
        XCTAssertNotNil(first)
        XCTAssertEqual(Array(first!.payload.prefix(3)), [0x03, 0x01, 0x00], "mode 3, frame id 1")
        XCTAssertNil(s.makeMapFrame(jpeg: jpeg, now: 2.1), "second frame must wait for the ACK")
        _ = s.receive(frame(ack80), now: 2.2)
        let second = s.makeMapFrame(jpeg: jpeg, now: 2.3)
        XCTAssertEqual(Array(second!.payload.prefix(3)), [0x03, 0x02, 0x00], "frame id 2")
    }

    func testLostAckDoesNotStallForever() {
        var s = DashSession()
        let jpeg = [UInt8](repeating: 0x11, count: 6000)
        _ = s.receive(frame(show55), now: 0)
        XCTAssertNotNil(s.makeMapFrame(jpeg: jpeg, now: 0))
        _ = s.tick(now: DashSession.ackTimeout + 0.1)
        XCTAssertNotNil(s.makeMapFrame(jpeg: jpeg, now: DashSession.ackTimeout + 0.2))
    }

    func testPauseStopsFramesAndNextShowResendsBottomBar() {
        var s = DashSession()
        let jpeg = [UInt8](repeating: 0x11, count: 6000)
        _ = s.receive(frame(show55), now: 0)
        _ = s.setBottomBar("Điện Biên Phủ")
        let out = s.receive(frame(pause56), now: 1)
        XCTAssertEqual(out.events, [.stopStreaming])
        XCTAssertEqual(summary(out.send), ["20/0/"], "pause is answered with 20 (documented)")
        XCTAssertNil(s.makeMapFrame(jpeg: jpeg, now: 1.1), "no frames while paused")

        // The dash forgets the bottom bar across a pause: it must be resent on the next 55.
        let reply = s.receive(frame(show55), now: 2).send
        XCTAssertEqual(reply.map { $0.command }, [2, 14, 13, 3, 10, 11])
        XCTAssertEqual(String(decoding: reply[3].payload, as: UTF8.self), "Điện Biên Phủ")
    }

    func testFrameIdsWrapFrom65535ToOne() {
        var s = DashSession()
        let jpeg = [UInt8](repeating: 0x11, count: 6000)
        _ = s.receive(frame(show55), now: 0)
        var last: Frame?
        for i in 1...65536 {
            last = s.makeMapFrame(jpeg: jpeg, now: Double(i))
            _ = s.receive(frame(ack80), now: Double(i) + 0.5)
        }
        // After 65535 frames (ids 1...65535) the 65536th frame wraps to id 1, never 0.
        XCTAssertEqual(Array(last!.payload.prefix(3)), [0x03, 0x01, 0x00])
    }
}
