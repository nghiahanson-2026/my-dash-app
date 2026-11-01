/// Turns the byte stream from the dash into frames.
///
/// Bytes arrive in arbitrary chunks: buffer them, find the magic, drop anything before it.
/// An absurd length (above 1 MiB) skips one byte and scans again. A frame with a wrong CRC is reported
/// and skipped. (docs/protocol/link-a-dash.md "Reading frames": a robust-decoder choice, not a bike rule.)
public struct FrameDecoder {
    public enum Event: Equatable {
        case frame(Frame)
        case badCRC(command: UInt8)
    }

    public static let maxPayload = 1 << 20
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func feed(_ bytes: [UInt8]) -> [Event] {
        buffer += bytes
        var events: [Event] = []
        while true {
            guard let start = findMagic() else {
                // Keep the last 3 bytes: they may be the start of a magic split across chunks.
                if buffer.count > 3 { buffer.removeFirst(buffer.count - 3) }
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            if buffer.count < Frame.headerSize { break }

            let length = Int(readLE32(at: 7))
            if length > FrameDecoder.maxPayload { buffer.removeFirst(); continue }
            if buffer.count < Frame.headerSize + length { break }

            let stored = readLE32(at: 12)
            let payload = Array(buffer[Frame.headerSize..<(Frame.headerSize + length)])
            let computed = CRC32MPEG2.checksum(Array(buffer[0..<12]) + payload)
            if computed != stored {
                events.append(.badCRC(command: buffer[6]))
                buffer.removeFirst()   // rescan from the next byte
                continue
            }
            events.append(.frame(Frame(direction: buffer[5], command: buffer[6], flag: buffer[11], payload: payload)))
            buffer.removeFirst(Frame.headerSize + length)
        }
        return events
    }

    private func readLE32(at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 {
            value |= UInt32(buffer[offset + i]) << UInt32(8 * i)
        }
        return value
    }

    private func findMagic() -> Int? {
        let m = Frame.magic
        guard buffer.count >= m.count else { return nil }
        for i in 0...(buffer.count - m.count)
        where buffer[i] == m[0] && buffer[i + 1] == m[1] && buffer[i + 2] == m[2] && buffer[i + 3] == m[3] {
            return i
        }
        return nil
    }
}
