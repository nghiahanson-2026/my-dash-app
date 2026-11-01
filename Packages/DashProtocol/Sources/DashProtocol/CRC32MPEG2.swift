/// CRC-32/MPEG-2: polynomial 0x04C11DB7, MSB first, init 0xFFFFFFFF, no reflection, no final XOR.
/// Check value for ASCII "123456789" is 0x0376E6E7. (docs/protocol/link-a-dash.md)
public enum CRC32MPEG2 {
    public static func checksum(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte) << 24
            for _ in 0..<8 {
                crc = (crc & 0x8000_0000) != 0 ? (crc << 1) ^ 0x04C1_1DB7 : (crc << 1)
            }
        }
        return crc
    }
}
