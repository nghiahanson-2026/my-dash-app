import Foundation

/// Builders for every frame the phone sends on Link A.
/// Each doc row says whether the bike has confirmed it; the notes below repeat the weaker ones.
public enum LinkA {
    public enum Command {
        public static let mapFrame: UInt8 = 0
        public static let navigationState: UInt8 = 2
        public static let bottomBarText: UInt8 = 3
        public static let home: UInt8 = 10
        public static let work: UInt8 = 11
        public static let init12: UInt8 = 12
        public static let init13: UInt8 = 13
        public static let label: UInt8 = 14
        public static let speedLimit: UInt8 = 17
        public static let pauseAck: UInt8 = 20
        public static let init31: UInt8 = 31
        public static let hello33: UInt8 = 33
        public static let handlebarUp: UInt8 = 51
        public static let handlebarDown: UInt8 = 52
        public static let showFrames: UInt8 = 55
        public static let pause: UInt8 = 56
        public static let bikeSpeed: UInt8 = 65
        public static let serial: UInt8 = 66
        public static let frameAck: UInt8 = 80
        public static let hello81: UInt8 = 81
        public static let authResult: UInt8 = 82
        public static let challenge: UInt8 = 83
        public static let challengeResponse: UInt8 = 84
    }

    /// Dash bottom-bar text is UTF-8, at most 144 bytes, cut on a character boundary.
    public static let maxBottomBarBytes = 144
    /// JPEGs of 2048 bytes or less are zero-padded by the dash; never send one that small.
    public static let minSafeJPEGBytes = 2049

    // MARK: Handshake

    public static func hello() -> [Frame] {
        [
            .phone(Command.hello81, payload: [0x01, 0x00]),
            .phone(Command.hello33, flag: 1, payload: [0x7C, 0x06, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]),
        ]
    }

    public static func challengeResponse(key: [UInt8]) -> Frame {
        .phone(Command.challengeResponse, flag: 1, payload: key)
    }

    // MARK: Small commands (flag 0 values are 2 bytes: [value, 00])

    public static func navigationState(navigating: Bool) -> Frame {
        .phone(Command.navigationState, payload: [navigating ? 1 : 0, 0])
    }
    public static func homeSaved(_ saved: Bool) -> Frame {
        .phone(Command.home, payload: [saved ? 1 : 0, 0])
    }
    public static func workSaved(_ saved: Bool) -> Frame {
        .phone(Command.work, payload: [saved ? 1 : 0, 0])
    }
    public static func init13() -> Frame { .phone(Command.init13, payload: [0x01, 0x00]) }
    public static func init31() -> Frame { .phone(Command.init31, payload: [0x01, 0x00]) }
    /// documented, not yet observed
    public static func init12() -> Frame { .phone(Command.init12, payload: [0x01, 0x00]) }
    /// documented, not yet observed
    public static func pauseAck() -> Frame { .phone(Command.pauseAck) }

    /// Empty label. Part of the init, and the reply the dash needs after every handlebar press,
    /// otherwise only the first press of the session arrives.
    public static func rearmButtons() -> Frame {
        .phone(Command.label, flag: 1, payload: [0x07, 0x1A, 0x00, 0x00])
    }

    // MARK: Bottom bar and speed sign

    /// The dash draws "▲ <text>". Flag must be 1 (with flag 0 the dash ignores it).
    /// An empty text becomes a single space, which clears it.
    public static func bottomBar(_ text: String) -> Frame {
        var bytes: [UInt8] = []
        for character in text {
            let encoded = Array(String(character).utf8)
            if bytes.count + encoded.count > maxBottomBarBytes { break }
            bytes += encoded
        }
        if bytes.isEmpty { bytes = [0x20] }
        return .phone(Command.bottomBarText, flag: 1, payload: bytes)
    }

    /// The dash's own red-ring speed sign. nil or 0 removes it. Flag must be 1.
    public static func speedLimit(_ kmh: Float?) -> Frame {
        let bits = (kmh ?? 0).bitPattern
        let unit = Array("km/h".utf8)
        let payload = Frame.le32(bits) + [UInt8(unit.count)] + unit
        return .phone(Command.speedLimit, flag: 1, payload: payload)
    }

    // MARK: Map frames

    /// Mode 3 = plain map (the dash draws only its fixed chrome over it).
    /// Frame id 1...65535. Returns nil for a JPEG too small to be safe.
    public static func mapFrame(id: UInt16, jpeg: [UInt8], mode: UInt8 = 3) -> Frame? {
        guard jpeg.count >= minSafeJPEGBytes, id != 0 else { return nil }
        let payload = [mode, UInt8(id & 0xFF), UInt8(id >> 8)] + jpeg
        return .phone(Command.mapFrame, flag: 1, payload: payload)
    }

    // MARK: Sequences

    /// The init sequence, in the observed order. Sent after the handshake.
    public static func initSequence(homeSaved: Bool = false, workSaved: Bool = false, bottomBar text: String = "") -> [Frame] {
        [
            navigationState(navigating: false),
            init31(),
            self.homeSaved(homeSaved),
            rearmButtons(),
            self.workSaved(workSaved),
            init13(),
            bottomBar(text),
            speedLimit(nil),
            init12(),
        ]
    }

    /// Reply to 55 (rider pressed Home). The dash forgets the bottom-bar text across a pause,
    /// so it is resent every time.
    public static func showFramesReply(homeSaved: Bool = false, workSaved: Bool = false, bottomBar text: String = "") -> [Frame] {
        [
            navigationState(navigating: false),
            rearmButtons(),
            init13(),
            bottomBar(text),
            self.homeSaved(homeSaved),
            self.workSaved(workSaved),
        ]
    }
}
