/// One Link A message, in either direction.
///
/// Layout (docs/protocol/link-a-dash.md): magic "nAl@" (4), version 01 (1), direction (1), command (1),
/// payload length u32 LE (4), flag (1), CRC u32 LE (4), payload (n).
/// The CRC covers the first 12 bytes, then the payload.
public struct Frame: Equatable {
    public static let magic: [UInt8] = [0x6E, 0x41, 0x6C, 0x40]
    public static let headerSize = 16
    public static let phoneDirection: UInt8 = 0x06

    public var direction: UInt8
    public var command: UInt8
    public var flag: UInt8
    public var payload: [UInt8]

    public init(direction: UInt8, command: UInt8, flag: UInt8 = 0, payload: [UInt8] = []) {
        self.direction = direction
        self.command = command
        self.flag = flag
        self.payload = payload
    }

    /// A frame the phone sends.
    public static func phone(_ command: UInt8, flag: UInt8 = 0, payload: [UInt8] = []) -> Frame {
        Frame(direction: phoneDirection, command: command, flag: flag, payload: payload)
    }

    public func encoded() -> [UInt8] {
        var head = Frame.magic
        head += [0x01, direction, command]
        head += Frame.le32(UInt32(payload.count))
        head.append(flag)
        let crc = CRC32MPEG2.checksum(head + payload)
        return head + Frame.le32(crc) + payload
    }

    static func le32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }
}
