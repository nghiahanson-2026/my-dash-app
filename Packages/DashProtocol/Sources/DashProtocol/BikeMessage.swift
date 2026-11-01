/// What a frame from the bike means.
public struct ScreenSize: Equatable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }

    /// Screen size from the dash part number (cmd 83).
    /// 006-B3952-01 = 480x234 (observed). 006-B4160... = 480x240 (documented, not yet observed).
    /// Anything else: treat as 480x234 (assumed) and please send a bike report.
    public static func forPart(_ part: String) -> ScreenSize {
        part.contains("006-B4160") ? ScreenSize(width: 480, height: 240) : ScreenSize(width: 480, height: 234)
    }
}

public enum BikeMessage: Equatable {
    case serial(String)
    case authenticated(Bool)
    case challenge(part: String, key: [UInt8], screen: ScreenSize)
    case showFrames
    case pause
    case speed(Int, isMph: Bool)
    case up
    case down
    case ack(frameID: UInt16)
    case other(command: UInt8, payload: [UInt8])

    public static func parse(_ frame: Frame) -> BikeMessage {
        let p = frame.payload
        switch frame.command {
        case LinkA.Command.serial:
            return .serial(String(decoding: p, as: UTF8.self))
        case LinkA.Command.authResult:
            return .authenticated(p.first == 1)
        case LinkA.Command.challenge:
            // 12-byte part number then a 4-byte key, every byte XOR 0x0A.
            guard p.count >= 16 else { break }
            let plain = p.map { $0 ^ 0x0A }
            let part = String(decoding: plain[0..<12], as: UTF8.self)
            return .challenge(part: part, key: Array(plain[12..<16]), screen: .forPart(part))
        case LinkA.Command.showFrames:
            // 55 `01 00` = show frames. 55 `03`/`04` open a list (documented, not used here).
            if p.first == 1 { return .showFrames }
        case LinkA.Command.pause:
            // 56 `03`/`04` close a list (documented). Anything else is a pause.
            if p.count == 1, p[0] == 3 || p[0] == 4 { break }
            return .pause
        case LinkA.Command.bikeSpeed:
            // u16 LE at bytes 1-2. Byte 0 = 01 would mean mph (assumed).
            guard p.count >= 3 else { break }
            return .speed(Int(p[1]) | Int(p[2]) << 8, isMph: p[0] == 1)
        case LinkA.Command.handlebarUp:
            return .up
        case LinkA.Command.handlebarDown:
            return .down
        case LinkA.Command.frameAck:
            // Send-to-ACK timing is observed; the payload encoding (u16 LE frame id) is documented only.
            guard p.count >= 2 else { break }
            return .ack(frameID: UInt16(p[0]) | UInt16(p[1]) << 8)
        default:
            break
        }
        return .other(command: frame.command, payload: p)
    }
}
